open Model

type config = { executable : string; gateway : Gateway.t option }

let configure ~executable ~gateway_file =
  if Filename.is_relative executable || String.contains executable '\000' then
    Error "Live Codex executable must be an absolute path."
  else
    try
      Unix.access executable [ Unix.X_OK ];
      if (Unix.stat executable).Unix.st_kind <> Unix.S_REG then
        Error "Codex executable must be a regular file."
      else
        match gateway_file with
        | None -> Ok { executable; gateway = None }
        | Some file ->
            Result.map
              (fun gateway -> { executable; gateway = Some gateway })
              (Gateway.load file)
    with Unix.Unix_error _ -> Error "Cannot access live Codex executable."

let prepare config (task : task) =
  if task.harness <> Codex then Error "Live mode supports Codex only."
  else if task.state = Working || task.state = Done then
    Error "Task cannot start in this state."
  else
    match task.workspace with
    | None ->
        Error "Live execution requires an isolated workspace task. Create one with W."
    | Some workspace
      when not (Sys.file_exists (Filename.concat workspace.directory ".jj")) ->
        Error "Recorded workspace is no longer a jj checkout."
    | Some workspace -> (
        let prompt =
          String.concat "\n\n"
            (List.filter_map
               (fun (m : message) -> if m.queued then Some m.text else None)
               task.messages)
        in
        if String.trim prompt = "" then
          Error "Post an instruction before starting another run."
        else if String.length prompt > 1048576 then
          Error "Combined queued prompt exceeds 1 MiB."
        else
          match
            Codex.invocation ~executable:config.executable ~directory:workspace.directory
              ~model:task.model ~thread_id:task.thread_id
          with
          | Error error -> Error error
          | Ok invocation ->
              Ok
                ( (match config.gateway with
                  | None -> invocation
                  | Some gateway -> Codex.with_gateway invocation gateway),
                  prompt ))

type context = {
  tasks : unit -> Model.task list;
  snapshot : unit -> Snapshot.t;
  pending_events : unit -> Model.envelope list;
  acknowledge_events : unit -> unit;
  receive : Model.envelope -> unit;
  report_error : string -> unit;
  quitting : unit -> bool;
}

type run = {
  task_id : string;
  run_id : string;
  thread_id : string option;
  handle : Run_handle.t;
  mutable identity_failed : bool;
}

type t = { config : config; mutable runs : run list }

let create config = { config; runs = [] }

let active context run =
  List.exists
    (fun (task : task) ->
      task.id = run.task_id && task.state = Working
      && match task.active with Some active -> active.id = run.run_id | None -> false)
    (context.tasks ())

let send context run event =
  context.receive { task_id = run.task_id; run_id = run.run_id; event }

let deliver context run =
  List.iter
    (fun (decoded : Harness.decoded) ->
      match decoded.event with
      | Some (Thread_started actual)
        when Option.fold ~none:false ~some:(( <> ) actual) run.thread_id ->
          run.identity_failed <- true;
          Run_handle.cancel run.handle;
          send context run (Failed "Harness returned a different resume thread.")
      | Some event when not run.identity_failed -> send context run event
      | _ -> ())
    (Run_handle.drain run.handle)

let poll runner context ~storage =
  runner.runs <-
    List.filter
      (fun run ->
        if (not (active context run)) || Persistence.error storage <> None then
          Run_handle.cancel run.handle;
        deliver context run;
        match Run_handle.outcome run.handle with
        | None -> true
        | Some outcome ->
            deliver context run;
            (match outcome with
            | Error error ->
                send context run (Failed error);
                send context run (Exited 1);
                context.report_error error
            | Ok _ when run.identity_failed -> send context run (Exited 1)
            | Ok result when result.interrupted -> send context run Interrupted
            | Ok result ->
                send context run
                  (Exited (match result.status with Unix.WEXITED code -> code | _ -> 1)));
            Run_handle.close run.handle;
            false)
      runner.runs;
  if not (context.quitting ()) then
    List.iter
      (fun (task : task) ->
        match task.active with
        | Some active
          when List.exists
                 (fun (record : run_record) ->
                   record.run_id = active.id && not record.simulated)
                 task.runs
               && not
                    (List.exists
                       (fun run -> run.task_id = task.id && run.run_id = active.id)
                       runner.runs) -> (
            let captured =
              List.find (fun (record : run_record) -> record.run_id = active.id) task.runs
            in
            let inspect =
              {
                task with
                state = Needs_you;
                active = None;
                model = captured.model;
                harness = captured.harness;
              }
            in
            match prepare runner.config inspect with
            | Error error ->
                context.receive
                  { task_id = task.id; run_id = active.id; event = Failed error };
                context.receive
                  { task_id = task.id; run_id = active.id; event = Exited 1 };
                context.report_error error
            | Ok (invocation, _) ->
                let prompt =
                  String.concat "\n\n"
                    (List.filter_map
                       (fun (m : message) ->
                         if List.mem m.id active.submitted then Some m.text else None)
                       task.messages)
                in
                let snapshot = context.snapshot () in
                let submitted =
                  Persistence.submit storage snapshot ~events:(context.pending_events ())
                in
                (match submitted with
                | Ok () -> context.acknowledge_events ()
                | Error _ -> ());
                let checkpoint () =
                  match submitted with
                  | Error error -> Error error
                  | Ok () -> Persistence.flush storage
                in
                let handle = Run_handle.start ~checkpoint invocation ~prompt in
                runner.runs <-
                  runner.runs
                  @ [
                      {
                        task_id = task.id;
                        run_id = active.id;
                        thread_id = task.thread_id;
                        handle;
                        identity_failed = false;
                      };
                    ])
        | _ -> ())
      (context.tasks ())

let close runner context =
  List.iter (fun run -> Run_handle.cancel run.handle) runner.runs;
  List.iter
    (fun run ->
      Run_handle.close run.handle;
      deliver context run;
      if active context run then send context run Interrupted)
    runner.runs;
  runner.runs <- []
