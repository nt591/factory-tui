open Factory_tui
open Model

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let await runner controller worker predicate =
  let deadline = Unix.gettimeofday () +. 5. in
  while (not (predicate ())) && Unix.gettimeofday () < deadline do
    Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
    Thread.delay 0.01
  done;
  check "live fixture finishes before deadline" (predicate ())

let () =
  let temporary = Filename.temp_file "factory-live-fixture" "" in
  Sys.remove temporary;
  Unix.mkdir temporary 0o700;
  let temporary = Unix.realpath temporary in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then (
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path)
    else Sys.remove path
  in
  Scope.on_exit
    (fun () -> remove temporary)
    (fun () ->
      let source = Filename.concat temporary "source" in
      Unix.mkdir source 0o700;
      ignore
        (ok
           (Command.run ~executable:"/opt/homebrew/bin/jj"
              ~arguments:[ "git"; "init"; "--colocate" ]
              ~directory:source ~timeout:15. ~max_output:2097152));
      let workspace =
        ok
          (Workspace.create ~jj:"/opt/homebrew/bin/jj" ~source
             ~destination:(Filename.concat temporary "task")
             ~revision:"@")
      in
      let task =
        ok
          (Model.attach_workspace
             (Model.make ~id:"task" ~title:"Fixture instruction" ~repository:source)
             (Workspace.reference workspace))
      in
      let executable = Filename.concat temporary "fixture-codex" in
      let write script =
        let channel = open_out executable in
        output_string channel ("#!/bin/sh\n" ^ script);
        close_out channel;
        Unix.chmod executable 0o700
      in
      let marker = Filename.concat (Workspace.destination workspace) "started" in
      write
        {|printf '%s\n' "$@" > arguments.txt
cat > prompt.txt
touch started
printf '%s\n' '{"type":"thread.started","thread_id":"fixture-thread"}'
printf '%s\n' '{"type":"turn.started"}'
sleep 0.1
printf '%s\n' '{"type":"item.updated","item":{"type":"agent_message","id":"reply","text":"part"}}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","id":"reply","text":"Fixture complete"}}'
printf '%s\n' '{"type":"turn.completed"}'
|};
      let config = ok (Live_runner.configure ~executable ~gateway_file:None) in
      let controller = Controller.create () in
      check "live config alone starts no process" (not (Sys.file_exists marker));
      check "live enable needs storage"
        (Result.is_error (Controller.enable_live controller config));
      let database = Filename.concat temporary "board.sqlite" in
      let worker, _ = ok (Persistence.start database) in
      Scope.on_exit
        (fun () -> ignore (Persistence.close worker))
        (fun () ->
          controller.database_path <- Some database;
          controller.retain_events <- true;
          controller.tasks <- [ task ];
          controller.selected <- task.id;
          ok (Controller.enable_live controller config);
          check "enable live clears demo scheduler"
            (controller.schedules = [] && not (Sys.file_exists marker));
          let runner = Live_runner.create config in
          Scope.on_exit
            (fun () -> Live_runner.close runner (Controller.live_context controller))
            (fun () ->
              Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
              check "idle poll starts nothing" (not (Sys.file_exists marker));
              Controller.act controller Controller.Start;
              check "Start records live run directly without confirmation"
                ((Option.get (Controller.selected controller)).state = Working);
              Controller.paste_key controller (`Enter, []);
              check "paste does not create an additional run"
                (List.length (Option.get (Controller.selected controller)).runs = 1
                && not (Sys.file_exists marker));
              check "confirmed task records live origin"
                (not
                   (List.hd (Option.get (Controller.selected controller)).runs).simulated);
              controller.tasks <-
                List.map
                  (fun (task : task) -> ok (Model.set_model task "next-model"))
                  controller.tasks;
              let captured_id =
                (Option.get (Option.get (Controller.selected controller)).active).id
              in
              Controller.receive controller
                { task_id = task.id; run_id = captured_id; event = Turn_started };
              check "captured prompt survives acknowledgement before spawn"
                (not
                   (List.exists
                      (fun (message : Model.message) ->
                        message.text = "Fixture instruction" && message.queued)
                      (Option.get (Controller.selected controller)).messages));
              let future_messages =
                List.init 17 (fun index ->
                    {
                      Model.id = Printf.sprintf "future-%d" index;
                      author = "You";
                      text = String.make 65536 'f';
                      queued = true;
                    })
              in
              controller.tasks <-
                List.map
                  (fun (task : task) ->
                    { task with messages = task.messages @ future_messages })
                  controller.tasks;
              check "later queue exceeds next-run preflight bound"
                (Result.is_error
                   (Live_runner.prepare config
                      {
                        (Option.get (Controller.selected controller)) with
                        state = Needs_you;
                        active = None;
                      }));
              Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
              Controller.act controller Controller.Begin_compose;
              Controller.set_input controller "Later reply";
              Controller.submit controller;
              await runner controller worker (fun () ->
                  (Option.get (Controller.selected controller)).state = Ready);
              let result = Option.get (Controller.selected controller) in
              check "streamed fixture produces single live message"
                (List.length
                   (List.filter (fun (m : message) -> m.author = "Codex") result.messages)
                = 1);
              check "thread recorded" (result.thread_id = Some "fixture-thread");
              let channel =
                open_in (Filename.concat (Workspace.destination workspace) "prompt.txt")
              in
              let prompt = really_input_string channel (in_channel_length channel) in
              close_in channel;
              check "confirmed run sends only original captured instruction"
                (prompt = "Fixture instruction");
              check "later large replies remain queued after earlier turn"
                (List.length
                   (List.filter
                      (fun (message : Model.message) ->
                        String.starts_with ~prefix:"future-" message.id)
                      result.messages)
                 = 17
                && List.for_all
                     (fun (message : Model.message) -> message.queued)
                     (List.filter
                        (fun (message : Model.message) ->
                          String.starts_with ~prefix:"future-" message.id)
                        result.messages));
              controller.tasks <-
                List.map
                  (fun (task : task) ->
                    {
                      task with
                      messages =
                        List.filter
                          (fun (message : Model.message) ->
                            not (String.starts_with ~prefix:"future-" message.id))
                          task.messages;
                    })
                  controller.tasks;

              check "late message stays queued"
                (List.exists
                   (fun (m : message) -> m.text = "Later reply" && m.queued)
                   result.messages);
              let channel =
                open_in
                  (Filename.concat (Workspace.destination workspace) "arguments.txt")
              in
              let arguments = really_input_string channel (in_channel_length channel) in
              close_in channel;
              check "captured run model used"
                ((not (Controller.contains arguments "next-model"))
                && Controller.contains arguments "coding-large");
              let observer = Sqlite3.db_open ~mode:`READONLY database in
              let stmt = Sqlite3.prepare observer "SELECT payload FROM snapshot" in
              check "Working snapshot exists before output"
                (Sqlite3.step stmt = Sqlite3.Rc.ROW);
              let saved = ok (Snapshot.decode (Sqlite3.column_text stmt 0)) in
              check "checkpoint belongs to confirmed task"
                ((List.hd saved.tasks).id = task.id);
              ignore (Sqlite3.finalize stmt);
              ignore (Sqlite3.db_close observer);
              write
                "cat >/dev/null\n\
                 printf '%s\\n' \
                 '{\"type\":\"thread.started\",\"thread_id\":\"wrong-thread\"}'\n\
                 sleep 1\n";
              Controller.act controller Controller.Start;
              ignore (Ui.render controller ~width:120 ~height:36);

              await runner controller worker (fun () ->
                  (Option.get (Controller.selected controller)).state = Needs_you);
              check "resume mismatch preserves recorded thread"
                ((Option.get (Controller.selected controller)).thread_id
               = Some "fixture-thread");
              let invalid_marker =
                Filename.concat
                  (Workspace.destination workspace)
                  "invalid-capture-started"
              in
              write "touch invalid-capture-started\ncat >/dev/null\n";
              let retained_queue =
                Run_prompt.queued (Option.get (Controller.selected controller))
              in
              Controller.act controller Controller.Start;
              ignore (Ui.render controller ~width:120 ~height:36);

              controller.tasks <-
                List.map
                  (fun (task : task) ->
                    {
                      task with
                      active =
                        Option.map
                          (fun (active : run) ->
                            {
                              active with
                              submitted = "missing-captured-message" :: active.submitted;
                            })
                          task.active;
                    })
                  controller.tasks;
              Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
              check "missing captured instruction refuses spawn"
                ((not (Sys.file_exists invalid_marker))
                && (Option.get (Controller.selected controller)).state = Needs_you
                && (Option.get (Controller.selected controller)).active = None);
              check "capture failure retains queued instructions for recovery"
                (Run_prompt.queued (Option.get (Controller.selected controller))
                = retained_queue);
              check "capture failure leaves a valid recoverable snapshot"
                (Result.is_ok
                   (Snapshot.decode (Snapshot.encode (Controller.snapshot controller))));
              check "capture failure is disclosed in task channel"
                (List.exists
                   (fun (message : message) ->
                     Controller.contains message.text "Captured instruction IDs")
                   (Option.get (Controller.selected controller)).messages);
              write "cat >/dev/null\nsleep 10\n";
              Controller.act controller Controller.Start;
              ignore (Ui.render controller ~width:120 ~height:36);

              Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
              Controller.act controller Controller.Stop;
              Live_runner.close runner (Controller.live_context controller);
              check "Stop cancels live task"
                ((Option.get (Controller.selected controller)).state = Needs_you);
              Controller.act controller Controller.Start;
              ignore (Ui.render controller ~width:120 ~height:36);

              Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
              Live_runner.close runner (Controller.live_context controller);
              check "shutdown records interruption"
                ((Option.get (Controller.selected controller)).active = None);
              let demo = Model.make ~id:"demo" ~title:"No workspace" ~repository:"demo" in
              check "demo cannot run live"
                (Result.is_error (Live_runner.prepare config demo));
              check "other harness refused"
                (Result.is_error
                   (Live_runner.prepare config { task with harness = Claude }));
              check "empty pending prompt refused"
                (Result.is_error (Live_runner.prepare config { task with messages = [] }));
              ok (Persistence.close worker);
              Controller.act controller Controller.Start;
              ignore (Ui.render controller ~width:120 ~height:36);

              Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
              await runner controller worker (fun () ->
                  (Option.get (Controller.selected controller)).state = Needs_you);
              check "failed checkpoint prevents new live process"
                ((Option.get (Controller.selected controller)).state = Needs_you)));
      let replay = Controller.create ~external_events:true () in
      replay.database_path <- Some "/fixture";
      check "replay cannot enable live"
        (Result.is_error (Controller.enable_live replay config)));
  Printf.printf "Passed %d live UI runner checks. Fake executable only.\n" !checks
