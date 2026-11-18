open Factory_tui
open Model
open Scope

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let temp = Filename.temp_file "factory-write-policy" "" in
  Sys.remove temp;
  Unix.mkdir temp 0o700;
  let temp = Unix.realpath temp in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then (
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path)
    else Sys.remove path
  in
  let@ () = Scope.on_exit (fun () -> remove temp) in
  let source = Filename.concat temp "source" in
  Unix.mkdir source 0o700;
  let jj = "/opt/homebrew/bin/jj" in
  let result =
    ok
      (Command.run ~executable:jj
         ~arguments:[ "git"; "init"; "--colocate" ]
         ~directory:source ~timeout:15. ~max_output:2097152)
  in
  check "temporary repository initialized" (result.status = Unix.WEXITED 0);
  let workspace =
    ok
      (Workspace.create ~jj ~source ~destination:(Filename.concat temp "task")
         ~revision:"@")
  in
  let task =
    ok
      (attach_workspace
         (make ~id:"write-task" ~title:"Implement a fixture" ~repository:source)
         (Workspace.reference workspace))
  in
  let executable = Filename.concat temp "fixture" in
  let channel = open_out executable in
  output_string channel
    {|#!/bin/sh
printf '%s\n' "$@" > arguments.txt
cat >/dev/null
case "$*" in
  *sandbox_mode=\"workspace-write\"*) ;;
  *) exit 2 ;;
esac
printf 'fixture implementation\n' > implementation.txt
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","id":"answer","text":"Fixture edit ready for review."}}'
printf '%s\n' '{"type":"turn.completed"}'
|};
  close_out channel;
  Unix.chmod executable 0o700;
  let readonly = ok (Live_runner.configure ~executable ~gateway_file:None) in
  check "configure defaults read-only" (Live_runner.policy readonly = Read_only);
  let config = Live_runner.with_policy readonly Workspace_write in
  check "write is explicit config change"
    (Live_runner.policy config = Workspace_write
    && Live_runner.policy readonly = Read_only);
  List.iter
    (fun thread_id ->
      let invocation =
        ok
          (Codex.invocation ~executable
             ~directory:(Workspace.destination workspace)
             ~model:"fixture-model" ~thread_id)
      in
      check "headless invocation retains Git repository check"
        (not (List.mem "--skip-git-repo-check" invocation.arguments));
      let prepared, _ = ok (Live_runner.prepare config { task with thread_id }) in
      check "recorded jj task bypasses only Git directory check"
        (List.mem "--skip-git-repo-check" prepared.arguments
        && List.mem {|approval_policy="never"|} prepared.arguments
        && List.mem {|sandbox_mode="workspace-write"|} prepared.arguments);
      let prepared_readonly, _ =
        ok (Live_runner.prepare readonly { task with thread_id })
      in
      check "jj repository exception does not weaken default sandbox policy"
        (List.mem "--skip-git-repo-check" prepared_readonly.arguments
        && List.mem {|sandbox_mode="read-only"|} prepared_readonly.arguments
        && List.mem {|approval_policy="never"|} prepared_readonly.arguments
        && not (List.mem {|sandbox_mode="workspace-write"|} prepared_readonly.arguments));
      check "jj adaptation preserves new and resume argument shapes"
        (match (thread_id, prepared.arguments) with
        | None, "exec" :: "--skip-git-repo-check" :: _ -> true
        | Some _, "exec" :: "resume" :: "--skip-git-repo-check" :: _ -> true
        | _ -> false);
      check "jj adaptation is idempotent and prompt stays on stdin"
        ((Codex.with_jj_workspace prepared).arguments = prepared.arguments
        && List.hd (List.rev prepared.arguments) = "-");
      let write = Codex.with_policy invocation Workspace_write in
      check "write override replaces rather than stacks read-only policy"
        (List.mem {|sandbox_mode="workspace-write"|} write.arguments
        && not (List.mem {|sandbox_mode="read-only"|} write.arguments));
      check "never approvals retained"
        (List.mem {|approval_policy="never"|} write.arguments);
      check "dangerous bypass not added"
        (not
           (List.exists
              (fun arg -> Controller.contains arg "dangerously")
              write.arguments));
      check "read-only can be selected explicitly"
        (List.mem {|sandbox_mode="read-only"|}
           (Codex.with_policy write Read_only).arguments))
    [ None; Some "recorded-thread" ];
  check "simulated writes rejected"
    (Result.is_error (start ~policy:Workspace_write task "run"));
  check "unattached writes rejected"
    (Result.is_error
       (start ~simulated:false ~policy:Workspace_write
          (make ~id:"demo" ~title:"demo" ~repository:"demo")
          "run"));
  let database = Filename.concat temp "board.sqlite" in
  let worker, _ = ok (Persistence.start database) in
  let@ () = Scope.on_exit (fun () -> ignore (Persistence.close worker)) in
  let controller = Controller.create () in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.database_path <- Some database;
  controller.retain_events <- true;
  ok (Controller.enable_live controller config);
  let runner = Live_runner.create config in
  let@ () =
    Scope.on_exit (fun () ->
        Live_runner.close runner (Controller.live_context controller))
  in
  let marker = Filename.concat (Workspace.destination workspace) "implementation.txt" in
  Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
  check "enabling write starts no process" (not (Sys.file_exists marker));
  Controller.act controller Controller.Start;
  let view =
    Live_confirmation.render ~policy:Workspace_write (Some task) ~width:88 ~height:24
  in
  let buffer = Buffer.create 4096 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (88, 24) view.image;
  check "write permission is visible before confirming"
    (Controller.contains (Buffer.contents buffer)
       "WRITE ACCESS: workspace + temp directories");
  Controller.paste_key controller (`ASCII 'y', []);
  check "paste cannot approve writes"
    ((Option.get (Controller.selected controller)).active = None
    && not (Sys.file_exists marker));
  ignore (Ui.render controller ~width:120 ~height:36);
  Controller.act controller Controller.Confirm_live;
  let captured = List.hd (Option.get (Controller.selected controller)).runs in
  check "run captures write policy"
    (captured.policy = Workspace_write && not captured.simulated);
  controller.live_config <- Some readonly;
  let deadline = Unix.gettimeofday () +. 5. in
  while
    (Option.get (Controller.selected controller)).state = Working
    && Unix.gettimeofday () < deadline
  do
    Live_runner.poll runner (Controller.live_context controller) ~storage:worker;
    Thread.delay 0.01
  done;
  let task = Option.get (Controller.selected controller) in
  check "fixture edit completes Ready" (task.state = Ready && Sys.file_exists marker);
  check "source checkout not edited"
    (not (Sys.file_exists (Filename.concat source "implementation.txt")));
  check "changing next policy does not alter recorded run"
    ((List.hd task.runs).policy = Workspace_write);
  let patch = ok (Workspace.diff ~jj workspace) in
  check "fixture writes appear in real diff"
    (Controller.contains patch "+fixture implementation");
  ok
    (Persistence.submit worker
       (Controller.snapshot controller)
       ~events:controller.storage_events);
  ok (Persistence.flush worker);
  let saved = ok (Snapshot.decode (Snapshot.encode (Controller.snapshot controller))) in
  check "policy survives snapshot round trip"
    ((List.hd (List.hd saved.tasks).runs).policy = Workspace_write);
  Controller.act controller Controller.Accept;
  check "acceptance changes only state"
    ((Option.get (Controller.selected controller)).state = Done && Sys.file_exists marker);
  let legacy = Yojson.Basic.from_string (Snapshot.encode saved) in
  let rec without_policy = function
    | `Assoc fields ->
        `Assoc
          (List.filter_map
             (fun (key, value) ->
               if key = "policy" then None else Some (key, without_policy value))
             fields)
    | `List values -> `List (List.map without_policy values)
    | value -> value
  in
  let legacy = ok (Snapshot.decode (Yojson.Basic.to_string (without_policy legacy))) in
  check "legacy policy defaults read-only"
    ((List.hd (List.hd legacy.tasks).runs).policy = Read_only);
  let broken =
    {
      saved with
      tasks =
        List.map
          (fun (task : task) ->
            {
              task with
              runs =
                List.map (fun (r : run_record) -> { r with simulated = true }) task.runs;
            })
          saved.tasks;
    }
  in
  check "persisted simulated write policy is invalid"
    (Result.is_error (Snapshot.decode (Snapshot.encode broken)));
  let invalid_policy = Yojson.Basic.from_string (Snapshot.encode saved) in
  let rec change_policy = function
    | `Assoc fields ->
        `Assoc
          (List.map
             (fun (key, value) ->
               ( key,
                 if key = "policy" then `String "danger-full-access"
                 else change_policy value ))
             fields)
    | `List values -> `List (List.map change_policy values)
    | value -> value
  in
  check "unknown persisted policy rejected"
    (Result.is_error
       (Snapshot.decode (Yojson.Basic.to_string (change_policy invalid_policy))));
  Printf.printf
    "Passed %d execution policy checks. Fixture writes in temporary workspace only.\n"
    !checks
