open Model

type context = {
  tasks : unit -> Model.task list;
  snapshot : unit -> Snapshot.t;
  pending_events : unit -> Model.envelope list;
  acknowledge_events : unit -> unit;
  receive : Model.envelope -> unit;
  report_error : string -> unit;
  enabled : unit -> bool;
  quitting : unit -> bool;
}

type run = { task_id : string; run_id : string; handle : Run_handle.t }
type t = { mutable runs : run list }

let create () = { runs = [] }

let script =
  {|cat >/dev/null
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.updated","item":{"type":"agent_message","id":"reply","text":"Local fixture is inspecting the task. No agent or model is running."}}'
sleep 0.4
printf '%s\n' '{"type":"item.completed","item":{"type":"command_execution","id":"inspect","command":"fixture only","status":"completed","exit_code":0,"aggregated_output":"Fixed local fixture output. No workspace changes."}}'
sleep 0.4
printf '%s\n' '{"type":"item.updated","item":{"type":"agent_message","id":"reply","text":"Local fixture checks are complete. Ready for your review."}}'
printf '%s\n' '{"type":"turn.completed"}'
|}

let active context run =
  List.exists
    (fun (task : task) ->
      task.id = run.task_id && task.state = Working
      && match task.active with Some active -> active.id = run.run_id | None -> false)
    (context.tasks ())

let deliver context run =
  List.iter
    (fun (decoded : Harness.decoded) ->
      Option.iter
        (fun event ->
          context.receive { task_id = run.task_id; run_id = run.run_id; event })
        decoded.event)
    (Run_handle.drain run.handle)

let poll runner context ~storage =
  runner.runs <-
    List.filter
      (fun run ->
        if not (active context run) then Run_handle.cancel run.handle;
        deliver context run;
        match Run_handle.outcome run.handle with
        | None -> true
        | Some outcome ->
            (* Completion is published after output stops; drain once more before exit. *)
            deliver context run;
            let send event =
              context.receive { task_id = run.task_id; run_id = run.run_id; event }
            in
            (match outcome with
            | Error error ->
                send (Failed error);
                send (Exited 1);
                context.report_error ("Fake harness error: " ^ error)
            | Ok result when result.interrupted -> send Interrupted
            | Ok result ->
                let code =
                  match result.status with Unix.WEXITED code -> code | _ -> 1
                in
                send (Exited code));
            Run_handle.close run.handle;
            false)
      runner.runs;
  if context.enabled () && not (context.quitting ()) then
    List.iter
      (fun (task : task) ->
        match task.active with
        | Some run
          when not
                 (List.exists
                    (fun existing ->
                      existing.task_id = task.id && existing.run_id = run.id)
                    runner.runs) ->
            let snapshot = context.snapshot () in
            let events = context.pending_events () in
            let queued =
              List.filter (fun (m : message) -> List.mem m.id run.submitted) task.messages
            in
            let prompt =
              String.concat "\n\n" (List.map (fun (m : message) -> m.text) queued)
            in
            let submitted =
              match storage with
              | None -> Ok ()
              | Some worker -> Persistence.submit worker snapshot ~events
            in
            (match submitted with
            | Ok () -> context.acknowledge_events ()
            | Error _ -> ());
            let checkpoint () =
              match (submitted, storage) with
              | Error error, _ -> Error error
              | Ok (), None -> Ok ()
              | Ok (), Some worker -> Persistence.flush worker
            in
            let config =
              Process.defaults ~executable:"/bin/sh" ~arguments:[ "-c"; script ]
                ~directory:(Sys.getcwd ())
            in
            let handle = Run_handle.start ~checkpoint config ~prompt in
            runner.runs <-
              runner.runs @ [ { task_id = task.id; run_id = run.id; handle } ]
        | _ -> ())
      (context.tasks ())

let close runner context =
  List.iter (fun run -> Run_handle.cancel run.handle) runner.runs;
  List.iter
    (fun run ->
      Run_handle.close run.handle;
      deliver context run;
      if active context run then
        context.receive
          { task_id = run.task_id; run_id = run.run_id; event = Interrupted })
    runner.runs;
  runner.runs <- []
