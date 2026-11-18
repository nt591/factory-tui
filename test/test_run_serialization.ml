open Factory_tui
open Model
open Scope

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let task controller id =
  List.find (fun (task : task) -> task.id = id) controller.Controller.tasks

let set_task (controller : Controller.t) (updated : Model.task) =
  controller.Controller.tasks <-
    List.map
      (fun (old : task) -> if old.id = updated.id then updated else old)
      controller.tasks

let confirm controller id =
  Controller.act controller (Controller.Select id);
  Controller.act controller Controller.Start;
  check "explicit confirmation required" (controller.live_confirmation = Some id);
  ignore (Ui.render controller ~width:120 ~height:36);
  Controller.act controller Controller.Confirm_live

let poll runner controller storage =
  Live_runner.poll runner (Controller.live_context controller) ~storage;
  controller.Controller.live_waiting_tasks <- Live_runner.waiting_tasks runner

let await predicate =
  let deadline = Unix.gettimeofday () +. 5. in
  while (not (predicate ())) && Unix.gettimeofday () < deadline do
    Thread.delay 0.01
  done;
  check "fixture condition observed before deadline" (predicate ())

let sql db statement =
  check "fixture SQLite statement succeeds" (Sqlite3.exec db statement = Sqlite3.Rc.OK)

let () =
  let temporary = Filename.temp_file "factory-run-slots" "" in
  Sys.remove temporary;
  Unix.mkdir temporary 0o700;
  let temporary = Unix.realpath temporary in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then (
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path)
    else Sys.remove path
  in
  let@ () = on_exit (fun () -> remove temporary) in
  let source = Filename.concat temporary "source" in
  Unix.mkdir source 0o700;
  let jj = "/opt/homebrew/bin/jj" in
  let initialized =
    ok
      (Command.run ~executable:jj
         ~arguments:[ "git"; "init"; "--colocate" ]
         ~directory:source ~timeout:15. ~max_output:2097152)
  in
  check "temporary repository initialized" (initialized.status = Unix.WEXITED 0);
  let workspace =
    ok
      (Workspace.create ~jj ~source
         ~destination:(Filename.concat temporary "first")
         ~revision:"@")
  in
  let independent =
    ok
      (Workspace.create ~jj ~source
         ~destination:(Filename.concat temporary "second")
         ~revision:"@")
  in
  let make_task id instruction reference =
    ok
      (Model.attach_workspace
         (Model.make ~id ~title:instruction ~repository:source)
         reference)
  in
  let first = make_task "first" "hold" (Workspace.reference workspace) in
  let alias_path = Filename.concat temporary "alias" in
  Unix.symlink (Workspace.destination workspace) alias_path;
  let alias =
    make_task "alias" "finish"
      { (Workspace.reference workspace) with directory = alias_path }
  in
  let separate = make_task "independent" "finish" (Workspace.reference independent) in
  let executable = Filename.concat temporary "fixture-codex" in
  let out = open_out executable in
  output_string out
    {|#!/bin/sh
prompt=$(cat)
case "$prompt" in
  hold) kind=hold ;;
  *retry*) kind=retry ;;
  *) kind=finish ;;
esac
printf '%s\n' "$$" > "started-$kind"
case "$kind" in
  hold) sleep 10 ;;
  *) printf '%s\n' '{"type":"turn.started"}'
     printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","id":"reply","text":"Finished fixture"}}'
     printf '%s\n' '{"type":"turn.completed"}' ;;
esac
|};
  close_out out;
  Unix.chmod executable 0o700;
  let config = ok (Live_runner.configure ~executable ~gateway_file:None) in
  let controller = Controller.create () in
  let database = Filename.concat temporary "board.sqlite" in
  let storage, _ = ok (Persistence.start database) in
  let@ () = on_exit (fun () -> ignore (Persistence.close storage)) in
  controller.tasks <- [ first; alias; separate ];
  controller.selected <- first.id;
  controller.database_path <- Some database;
  controller.retain_events <- true;
  ok (Controller.enable_live controller config);
  ok (Persistence.submit storage (Controller.snapshot controller) ~events:[]);
  ok (Persistence.flush storage);
  let runner = Live_runner.create config in
  let@ () =
    on_exit (fun () -> Live_runner.close runner (Controller.live_context controller))
  in
  confirm controller first.id;
  poll runner controller storage;
  await (fun () ->
      poll runner controller storage;
      Sys.file_exists (Filename.concat (Workspace.destination workspace) "started-hold"));
  confirm controller alias.id;
  confirm controller separate.id;
  poll runner controller storage;
  check "aliased workspace waits while original process runs"
    (Live_runner.waiting_tasks runner = [ alias.id ]);
  check "waiting run remains Working without process start"
    ((task controller alias.id).state = Working
    && not
         (Sys.file_exists
            (Filename.concat (Workspace.destination workspace) "started-finish")));
  await (fun () ->
      poll runner controller storage;
      (task controller separate.id).state = Ready);
  check "independent workspace runs concurrently"
    ((task controller first.id).state = Working
    && (task controller separate.id).state = Ready);
  check "workspace wait does not change selected conversation"
    (controller.selected = separate.id);
  Controller.act controller (Controller.Select alias.id);
  controller.focus <- Controller.Activity;
  controller.zoom <- true;
  controller.activity_expanded <- true;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 4096 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "workspace waiting state visible"
    (Controller.contains (Buffer.contents buffer)
       "Waiting for previous workspace process cleanup");
  Controller.act controller (Controller.Select first.id);
  Controller.act controller Controller.Stop;
  await (fun () ->
      poll runner controller storage;
      (task controller alias.id).state = Ready);
  check "waiting workspace starts after stopped owner cleanup"
    (Sys.file_exists (Filename.concat (Workspace.destination workspace) "started-finish"));
  check "old outcome cannot finish stopped task"
    ((task controller first.id).state = Needs_you);
  check "waiting list clears after launch" (Live_runner.waiting_tasks runner = []);

  let observer = Sqlite3.db_open database in
  let@ () =
    on_exit (fun () ->
        ignore (Sqlite3.exec observer "ROLLBACK");
        ignore (Sqlite3.db_close observer))
  in
  ok
    (Persistence.submit storage
       (Controller.snapshot controller)
       ~events:controller.storage_events);
  controller.storage_events <- [];
  ok (Persistence.flush storage);
  sql observer "BEGIN IMMEDIATE";
  confirm controller first.id;
  poll runner controller storage;
  Controller.act controller Controller.Stop;
  let before = task controller first.id in
  set_task controller (ok (Model.send before ~id:"replacement-message" "retry"));
  confirm controller first.id;
  poll runner controller storage;
  check "cancelled checkpoint retains slot for same task retry"
    (Live_runner.waiting_tasks runner = [ first.id ]);
  let replacement_id = (Option.get (task controller first.id).active).id in
  let paused = Controller.snapshot controller in
  let replacement_status = controller.status in
  for _ = 1 to 3 do
    poll runner controller storage
  done;
  check "waiting retry creates no overlapping process"
    (not
       (Sys.file_exists
          (Filename.concat (Workspace.destination workspace) "started-retry")));
  check "waiting poll preserves confirmed run identity"
    ((Option.get (task controller first.id).active).id = replacement_id
    && Controller.snapshot controller = paused
    && controller.status = replacement_status);
  sql observer "ROLLBACK";
  let context = Controller.live_context controller in
  let context =
    {
      context with
      report_error =
        (fun _ -> failwith "old prelaunch cancellation must not report an error");
    }
  in
  await (fun () ->
      Live_runner.poll runner context ~storage;
      (task controller first.id).state = Ready);
  check "retry runs after cancelled checkpoint is joined"
    (Sys.file_exists (Filename.concat (Workspace.destination workspace) "started-retry"));
  check "old cancellation does not terminate replacement"
    ((List.hd (List.rev (task controller first.id).runs)).status = Completed);
  check "replacement completion replaces waiting status with success guidance"
    (Controller.contains controller.status "Run complete.");

  set_task controller
    (ok (Model.send (task controller first.id) ~id:"closing-message" "hold"));
  confirm controller first.id;
  poll runner controller storage;
  set_task controller
    (ok (Model.send (task controller alias.id) ~id:"waiting-message" "finish"));
  confirm controller alias.id;
  poll runner controller storage;
  check "another confirmed task waits at shutdown"
    (List.mem alias.id (Live_runner.waiting_tasks runner));
  controller.quit <- true;
  Live_runner.close runner (Controller.live_context controller);
  check "shutdown interrupts both owned and waiting runs"
    ((task controller first.id).active = None
    && (task controller alias.id).active = None
    && (List.hd (List.rev (task controller first.id).runs)).status = Stopped
    && (List.hd (List.rev (task controller alias.id).runs)).status = Stopped);
  check "shutdown clears workspace wait state" (Live_runner.waiting_tasks runner = []);
  ok
    (Persistence.submit storage
       (Controller.snapshot controller)
       ~events:controller.storage_events);
  ok (Persistence.flush storage);
  Printf.printf "Passed %d workspace run serialization checks. Temporary fixtures only.\n"
    !checks
