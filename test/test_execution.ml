open Factory_tui
open Model

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let directory = Filename.temp_file "factory-execution" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let directory = Unix.realpath directory in
  Fun.protect
    ~finally:(fun () ->
      Array.iter
        (fun name -> Sys.remove (Filename.concat directory name))
        (Sys.readdir directory);
      Unix.rmdir directory)
    (fun () ->
      let database = Filename.concat directory "board.sqlite" in
      let executable = Filename.concat directory "fake-codex" in
      let write_script script =
        let channel = open_out executable in
        output_string channel ("#!/bin/sh\n" ^ script);
        close_out channel;
        Unix.chmod executable 0o700
      in
      let script =
        {|cat > prompt.txt
printf '%s\n' '{"type":"thread.started","thread_id":"fixture-thread"}'
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","id":"reply","text":"Fixture answer"}}'
printf '%s\n' '{"type":"turn.completed"}'
|}
      in
      write_script script;
      let run ?(thread_id = None) ?(prompt = "A task") ?(cancelled = fun () -> false) () =
        Execution.run ~executable ~directory ~model:"fixture-model" ~thread_id
          ~gateway_file:None ~database ~prompt ~cancelled
      in
      let load () =
        let store = ok (Storage.open_store database) in
        Fun.protect
          ~finally:(fun () -> Storage.close store)
          (fun () -> Option.get (ok (Storage.load store)))
      in
      let summary = ok (run ()) in
      check "execution finishes Ready" (summary.succeeded && summary.state = Ready);
      check "thread identity retained" (summary.thread_id = Some "fixture-thread");
      let saved = load () in
      let task = List.hd saved.tasks in
      check "task persisted" (task.id = summary.task_id && task.state = Ready);
      check "execution history not marked simulated" (not (List.hd task.runs).simulated);
      check "execution author distinguished from simulation"
        ((List.hd (List.rev task.messages)).author = "Codex");
      check "prompt acknowledged" (not (List.hd task.messages).queued);
      check "snapshot retains origin"
        (ok (Snapshot.decode (Snapshot.encode saved)) = saved);
      let legacy = Yojson.Basic.from_string (Snapshot.encode saved) in
      let rec without_origin = function
        | `Assoc fields ->
            `Assoc
              (List.filter_map
                 (fun (key, value) ->
                   if key = "simulated" then None else Some (key, without_origin value))
                 fields)
        | `List values -> `List (List.map without_origin values)
        | value -> value
      in
      let legacy =
        ok (Snapshot.decode (Yojson.Basic.to_string (without_origin legacy)))
      in
      check "older snapshots default to simulation"
        (List.for_all (fun (r : run_record) -> r.simulated) (List.hd legacy.tasks).runs);
      let summary = ok (run ~thread_id:(Some "fixture-thread") ~prompt:"Follow up" ()) in
      let task = List.hd (load ()).tasks in
      check "resume retains same task"
        (summary.task_id = task.id && List.length task.runs = 2);
      check "resume sends only queued reply"
        (let channel = open_in (Filename.concat directory "prompt.txt") in
         let prompt = really_input_string channel (in_channel_length channel) in
         close_in channel;
         prompt = "Follow up");
      write_script
        {|cat >/dev/null
printf '%s\n' '{"type":"thread.started","thread_id":"different-thread"}'
|};
      check "mismatched resume thread fails"
        (Result.is_error (run ~thread_id:(Some "fixture-thread") ()));
      check "mismatched thread does not replace identity"
        ((List.hd (load ()).tasks).thread_id = Some "fixture-thread");
      check "unknown resume thread refused"
        (Result.is_error (run ~thread_id:(Some "unknown") ()));
      check "empty prompt refused" (Result.is_error (run ~prompt:" " ()));
      check "oversized prompt refused"
        (Result.is_error (run ~prompt:(String.make 65537 'x') ()));
      write_script "cat >/dev/null\nexit 0\n";
      let summary = ok (run ()) in
      check "exit alone not success" ((not summary.succeeded) && summary.state = Needs_you);
      write_script "printf '%s\\n' 'bad JSON'\n";
      check "malformed harness error returned" (Result.is_error (run ()));
      check "malformed run persists Needs you"
        ((List.hd (List.rev (load ()).tasks)).state = Needs_you);
      let cancellation_marker = Filename.concat directory "cancellation-started" in
      write_script "touch cancellation-started\nsleep 10\n";
      let summary =
        ok (run ~cancelled:(fun () -> Sys.file_exists cancellation_marker) ())
      in
      check "runtime cancellation observes a launched fixture"
        (Sys.file_exists cancellation_marker);
      check "cancellation terminal state"
        (summary.state = Needs_you && not summary.succeeded);
      check "cancellation records interruption"
        ((List.hd (List.rev (List.hd (List.rev (load ()).tasks)).runs)).status = Stopped);
      let store = ok (Storage.open_store database) in
      check "database ownership prevents execution" (Result.is_error (run ()));
      Storage.close store;
      write_script "touch launched\n";
      check "prelaunch cancellation refuses execution"
        (Result.is_error (run ~cancelled:(fun () -> true) ()));
      check "prelaunch cancellation has no process effect"
        (not (Sys.file_exists (Filename.concat directory "launched")));
      let db = Sqlite3.db_open database in
      ignore
        (Sqlite3.exec db
           "CREATE TRIGGER reject_checkpoint BEFORE INSERT ON snapshot BEGIN SELECT \
            RAISE(ABORT,'fixture'); END");
      ignore (Sqlite3.db_close db);
      check "failed initial checkpoint refuses execution" (Result.is_error (run ()));
      check "failed checkpoint has no process effect"
        (not (Sys.file_exists (Filename.concat directory "launched"))));
  Printf.printf "Passed %d execution checks. Fake executable only.\n" !checks
