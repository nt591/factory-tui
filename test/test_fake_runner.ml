open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error
let select controller = Controller.act controller (Controller.Select "T-101")

let poll_until runner controller storage predicate =
  let deadline = Unix.gettimeofday () +. 3. in
  while (not (predicate ())) && Unix.gettimeofday () < deadline do
    Demo.Runner.poll runner (Controller.demo_context controller) ~storage;
    Thread.delay 0.01
  done;
  check "fixture completes before deadline" (predicate ())

let () =
  let controller = Controller.create ~fake_harness:true () in
  let runner = Demo.Runner.create () in
  Fun.protect
    ~finally:(fun () -> Demo.Runner.close runner (Controller.demo_context controller))
    (fun () ->
      check "fake mode has no startup runs"
        (controller.schedules = []
        && List.for_all (fun (t : task) -> t.active = None) controller.tasks);
      select controller;
      Demo.Runner.poll runner (Controller.demo_context controller) ~storage:None;
      check "poll does not start idle task"
        ((Option.get (Controller.selected controller)).state = Queued);
      Controller.act controller Controller.Start;
      Demo.Runner.poll runner (Controller.demo_context controller) ~storage:None;
      Controller.act controller Controller.Begin_compose;
      Controller.set_input controller "Reply while fixture works";
      Controller.submit controller;
      poll_until runner controller None (fun () ->
          (Option.get (Controller.selected controller)).state = Ready);
      let task = Option.get (Controller.selected controller) in
      check "process events move card to Ready"
        (task.state = Ready && controller.selected = "T-101");
      check "streamed fixture replaces same message"
        (List.length
           (List.filter
              (fun (m : message) -> m.author = "Codex (simulated)")
              task.messages)
        = 1);
      check "tools arrive from process" (List.length task.tools = 1);
      check "prompt delivery acknowledged" (not (List.hd task.messages).queued);
      check "late reply stays queued" (List.nth task.messages 1).queued;
      check "run completion recorded" ((List.hd task.runs).status = Completed);
      Controller.act controller Controller.Start;
      Demo.Runner.poll runner (Controller.demo_context controller) ~storage:None;
      Controller.act controller Controller.Stop;
      poll_until runner controller None (fun () ->
          (Option.get (Controller.selected controller)).state = Needs_you);
      check "stop keeps task Needs you"
        ((Option.get (Controller.selected controller)).state = Needs_you);
      Demo.Runner.close runner (Controller.demo_context controller);
      Demo.Runner.poll runner (Controller.demo_context controller) ~storage:None;
      check "late process events rejected"
        ((Option.get (Controller.selected controller)).state = Needs_you);
      Controller.act controller Controller.Start;
      Demo.Runner.poll runner (Controller.demo_context controller) ~storage:None;
      Demo.Runner.close runner (Controller.demo_context controller);
      check "close cancels active task"
        ((Option.get (Controller.selected controller)).active = None));
  let dir = Filename.temp_file "factory-fake-storage" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o700;
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun name -> Sys.remove (Filename.concat dir name)) (Sys.readdir dir);
      Unix.rmdir dir)
    (fun () ->
      let path = Filename.concat dir "board.sqlite" in
      let worker, _ = ok (Persistence.start path) in
      let controller = Controller.create ~fake_harness:true () in
      controller.retain_events <- true;
      let runner = Demo.Runner.create () in
      Fun.protect
        ~finally:(fun () ->
          Demo.Runner.close runner (Controller.demo_context controller);
          ignore (Persistence.close worker))
        (fun () ->
          select controller;
          Controller.act controller Controller.Start;
          Demo.Runner.poll runner
            (Controller.demo_context controller)
            ~storage:(Some worker);
          poll_until runner controller (Some worker) (fun () ->
              List.exists
                (fun (m : message) -> not m.queued)
                (Option.get (Controller.selected controller)).messages);
          let observer = Sqlite3.db_open ~mode:`READONLY path in
          let query = Sqlite3.prepare observer "SELECT payload FROM snapshot" in
          check "Working checkpoint readable before delivery"
            (Sqlite3.step query = Sqlite3.Rc.ROW);
          let saved = ok (Snapshot.decode (Sqlite3.column_text query 0)) in
          check "checkpoint contains active task"
            ((List.find (fun (t : task) -> t.id = "T-101") saved.tasks).state = Working);
          ignore (Sqlite3.finalize query);
          ignore (Sqlite3.db_close observer);
          Demo.Runner.close runner (Controller.demo_context controller);
          ok (Persistence.close worker)));
  let controller = Controller.create ~fake_harness:true () in
  let runner = Demo.Runner.create () in
  let dir = Filename.temp_file "factory-fake-reject" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o700;
  Fun.protect
    ~finally:(fun () ->
      Demo.Runner.close runner (Controller.demo_context controller);
      Array.iter (fun name -> Sys.remove (Filename.concat dir name)) (Sys.readdir dir);
      Unix.rmdir dir)
    (fun () ->
      let worker, _ = ok (Persistence.start (Filename.concat dir "board.sqlite")) in
      ok (Persistence.close worker);
      select controller;
      Controller.act controller Controller.Start;
      Demo.Runner.poll runner (Controller.demo_context controller) ~storage:(Some worker);
      poll_until runner controller (Some worker) (fun () ->
          (Option.get (Controller.selected controller)).state = Needs_you);
      check "failed checkpoint prevents fixture messages"
        (List.for_all
           (fun (m : message) -> m.author <> "Codex (simulated)")
           (Option.get (Controller.selected controller)).messages));
  Printf.printf "Passed %d fake-runner checks. No model calls.\n" !checks
