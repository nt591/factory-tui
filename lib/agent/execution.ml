open Model
open Scope

type summary = {
  task_id : string;
  thread_id : string option;
  state : Model.state;
  succeeded : bool;
}

exception Execution_error of string

let unwrap = function Ok value -> value | Error error -> raise (Execution_error error)

let checkpoint worker snapshot events =
  unwrap (Persistence.submit worker snapshot ~events);
  unwrap (Persistence.flush worker)

let title prompt =
  let buffer = Buffer.create 120 and count = ref 0 in
  Uutf.String.fold_utf_8
    (fun () _ character ->
      if !count < 120 then (
        incr count;
        let character =
          match character with `Uchar value -> value | `Malformed _ -> Uutf.u_rep
        in
        Uutf.Buffer.add_utf_8 buffer character))
    () prompt;
  Buffer.contents buffer

let run ~executable ~directory ~model ~thread_id ~gateway_file ~database ~prompt
    ~cancelled =
  try
    if String.trim prompt = "" then
      raise (Execution_error "Run requires a nonempty stdin prompt.");
    if String.length prompt > 65536 then
      raise (Execution_error "Run prompt exceeds 64 KiB.");
    if cancelled () then raise (Execution_error "Run cancelled before setup.");
    let config = unwrap (Codex.invocation ~executable ~directory ~model ~thread_id) in
    let config =
      match gateway_file with
      | None -> config
      | Some file -> Codex.with_gateway config (unwrap (Gateway.load file))
    in
    let directory = Unix.realpath directory in
    let worker, loaded = unwrap (Persistence.start database) in
    let closing_error = ref None in
    let result =
      let@ () =
        on_exit (fun () ->
            match Persistence.close worker with
            | Ok () -> ()
            | Error error -> closing_error := Some error)
      in
      let saved =
        match loaded with
        | None -> { Snapshot.tasks = []; drafts = []; selected = ""; serial = 200 }
        | Some saved -> Snapshot.recover saved
      in
      let serial = ref saved.serial in
      let next_id prefix =
        let rec next () =
          if !serial = max_int then
            raise (Execution_error "Session ID counter is exhausted.");
          incr serial;
          let id = Printf.sprintf "%s-%d" prefix !serial in
          if
            List.exists
              (fun (t : task) ->
                t.id = id || List.exists (fun (r : run_record) -> r.run_id = id) t.runs)
              saved.tasks
          then next ()
          else id
        in
        next ()
      in
      let task, fresh =
        match thread_id with
        | None ->
            let task = make ~id:(next_id "T") ~title:"Codex task" ~repository:directory in
            ({ task with messages = [] }, true)
        | Some id -> (
            match List.filter (fun (t : task) -> t.thread_id = Some id) saved.tasks with
            | [ task ] when task.repository = directory && task.harness = Codex ->
                (task, false)
            | [ _ ] ->
                raise
                  (Execution_error
                     "Resume workspace or harness does not match the saved task.")
            | [] ->
                raise (Execution_error "Resume thread is not recorded in this database.")
            | _ ->
                raise (Execution_error "Resume thread matches more than one saved task."))
      in
      let task = unwrap (set_model task model) in
      let task = unwrap (send task ~id:(next_id "message") prompt) in
      let task = if fresh then { task with title = title prompt } else task in
      let run_prompt =
        String.concat "\n\n"
          (List.filter_map
             (fun (m : message) -> if m.queued then Some m.text else None)
             task.messages)
      in
      if String.length run_prompt > 1048576 then
        raise (Execution_error "Combined queued prompt exceeds 1 MiB.");
      let run_id = next_id "run" in
      let task = unwrap (start ~simulated:false task run_id) in
      let current =
        ref
          {
            saved with
            tasks =
              (if fresh then saved.tasks @ [ task ]
               else
                 List.map
                   (fun (old : task) -> if old.id = task.id then task else old)
                   saved.tasks);
            selected = task.id;
            serial = !serial;
          }
      in
      (* Durability precedes process launch, including restart recovery. *)
      checkpoint worker !current [];
      let delivery_error = ref None in
      let observe event =
        (match (thread_id, event) with
        | Some expected, Thread_started actual when expected <> actual ->
            raise (Execution_error "Harness resumed a different thread than requested.")
        | _ -> ());
        let envelope = { task_id = task.id; run_id; event } in
        current := { !current with tasks = reduce !current.tasks envelope };
        match Persistence.submit worker !current ~events:[ envelope ] with
        | Ok () -> ()
        | Error error ->
            delivery_error := Some error;
            raise (Execution_error error)
      in
      let cancelled () = cancelled () || Persistence.error worker <> None in
      let result =
        Process.run config ~prompt:run_prompt ~cancelled
          ~on_event:(fun (decoded : Harness.decoded) -> Option.iter observe decoded.event)
      in
      (* Drain acknowledged writes before publishing a terminal snapshot. *)
      unwrap (Persistence.flush worker);
      let result =
        match !delivery_error with Some error -> Error error | None -> result
      in
      (match result with
      | Error error ->
          observe (Failed error);
          observe (Exited 1)
      | Ok result when result.interrupted -> observe Interrupted
      | Ok result ->
          observe (Exited (match result.status with Unix.WEXITED code -> code | _ -> 1)));
      checkpoint worker !current [];
      let final = List.find (fun (t : task) -> t.id = task.id) !current.tasks in
      let summary =
        {
          task_id = task.id;
          thread_id = final.thread_id;
          state = final.state;
          succeeded = final.state = Ready;
        }
      in
      match result with Error error -> Error error | Ok _ -> Ok summary
    in
    match !closing_error with Some error -> Error error | None -> result
  with
  | Execution_error error -> Error error
  | Unix.Unix_error _ | Sys_error _ -> Error "Execution file operation failed."
  | Invalid_argument _ -> Error "Invalid execution configuration."
