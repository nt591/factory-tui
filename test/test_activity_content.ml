open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let contains rows text = Controller.contains (String.concat "\n" rows) text

let () =
  let title = "Inspect " ^ String.make 160 'x' ^ " TITLE_END" in
  let repository = "/source/" ^ String.make 160 'r' ^ "/SOURCE_END" in
  let directory = "/tasks/" ^ String.make 160 'w' ^ "/WORKSPACE_END" in
  let base = String.make 40 'a' in
  let task =
    {
      (make ~id:"inspection" ~title ~repository) with
      workspace = Some { source = repository; directory; base; name = "fixture" };
      model = String.make 180 'm' ^ "MODEL_END";
      tools =
        [
          ( "run/command",
            {|{"type":"command_execution","command":"dune runtest","status":"completed","exit_code":0,"aggregated_output":"first output\nsecond output","unknown":"RAW_ONLY"}|}
          );
        ];
      runs =
        [
          {
            run_id = "run";
            harness = Codex;
            model = "recorded-model";
            started_at = 0.;
            ended_at = Some 1.;
            status = Completed;
            simulated = false;
            policy = Workspace_write;
          };
        ];
    }
  in
  let lines ?(expanded = true) ?(raw = false) ?(waiting = false) task =
    Activity_content.lines ~now:10. ~expanded ~raw ~waiting task
  in
  check "empty selection has actionable identity" (lines None = [ "No task selected." ]);
  let content = lines (Some task) in
  check "full title is retained" (List.hd content = title);
  check "full source path is retained" (List.mem ("repo: " ^ repository) content);
  check "full workspace path is retained" (List.mem ("workspace: " ^ directory) content);
  check "recorded review base is visible" (List.mem ("base: " ^ base) content);
  check "full next model is retained" (List.mem ("next: Codex / " ^ task.model) content);
  check "command and output stay readable"
    (contains content "$ dune runtest"
    && List.mem "first output" content
    && List.mem "second output" content);
  check "readable mode omits raw-only fields" (not (contains content "RAW_ONLY"));
  check "raw mode retains supplied extra fields"
    (contains (lines ~raw:true (Some task)) "RAW_ONLY");
  check "collapsed tools do not expose output"
    (contains (lines ~expanded:false (Some task)) "t expands"
    && not (contains (lines ~expanded:false (Some task)) "first output"));
  let collapsed = lines ~expanded:false (Some task) in
  check "collapsed tools expose supplied summary without command or output"
    (List.mem "Latest update: Command / completed / exit 0" collapsed
    && (not (contains collapsed "$ dune runtest"))
    && (not (contains collapsed "first output"))
    && not (contains collapsed "RAW_ONLY"));
  check "collapsed summary discloses recorded origin"
    (List.mem "Source run: run / Codex / recorded-model / live / workspace-write"
       collapsed);
  let updated =
    {
      task with
      tools =
        task.tools
        @ [
            ( "unrecorded/new",
              {|{"type":"mcp_tool_call","server":"files","tool":"read","status":"failed"}|}
            );
          ];
    }
  in
  let summary = lines ~expanded:false (Some updated) in
  check "latest update is the final reducer-ordered tool item"
    (List.mem "Latest update: MCP files/read / failed" summary
    && not (List.mem "Latest update: Command / completed / exit 0" summary));
  check "unrecorded summary does not invent live origin"
    (List.mem "Source run: not recorded" summary);
  let active =
    Result.get_ok
      (Model.start
         (make ~id:"latest-task" ~title:"Tool updates" ~repository:"fixture")
         "latest-run")
  in
  let tool_update task id payload =
    Option.get
      (Model.apply task
         { task_id = task.id; run_id = "latest-run"; event = Tool (id, payload) })
  in
  let first = {|{"type":"command_execution","status":"in_progress"}|} in
  let second = {|{"type":"file_change","status":"completed"}|} in
  let done_tool = {|{"type":"command_execution","status":"completed","exit_code":1}|} in
  let active = tool_update active "first" first in
  let active = tool_update active "second" second in
  let active = tool_update active "first" done_tool in
  let latest = lines ~expanded:false (Some active) in
  check "updated existing item becomes the latest summary without duplication"
    (List.length active.tools = 2
    && List.mem "Latest update: Command / completed / exit 1" latest);
  check "tool completion summary does not complete the run"
    (active.state = Working && active.active <> None);

  check "waiting status is explicit"
    (contains
       (lines ~waiting:true (Some task))
       "Waiting for previous workspace process cleanup.");
  check "run history keeps captured model and write policy"
    (contains content
       "run run: Codex / recorded-model / completed / live / workspace-write");
  check "terminal duration appears in activity history"
    (contains content "recorded duration 1s");
  let running =
    {
      task with
      runs =
        List.map
          (fun (run : run_record) -> { run with ended_at = None; status = Running })
          task.runs;
    }
  in
  check "active history reports run age" (contains (lines (Some running)) "run age 10s");
  let earlier =
    {
      (List.hd task.runs) with
      run_id = "earlier";
      harness = Claude;
      model = "old-model";
      policy = Read_only;
      simulated = true;
      ended_at = Some 2.;
    }
  in
  let latest =
    {
      (List.hd task.runs) with
      run_id = "latest";
      model = "latest-model";
      started_at = 5.;
      ended_at = Some 7.;
    }
  in
  let history = { task with runs = [ earlier; latest ] } in
  let origin_history =
    {
      history with
      tools =
        [
          ("earlier/same-item", snd (List.hd task.tools));
          ("latest/same-item", snd (List.hd task.tools));
        ];
    }
  in
  let origins = lines (Some origin_history) in
  check "historical tool origin retains captured simulated settings"
    (List.mem "Source run: earlier / Claude / old-model / simulated / read-only" origins);
  check "latest tool origin retains captured live write policy"
    (List.mem "Source run: latest / Codex / latest-model / live / workspace-write" origins);
  check "raw tool inspection keeps origin disclosure"
    (contains
       (lines ~raw:true (Some origin_history))
       "Source run: earlier / Claude / old-model / simulated / read-only");
  let overlapping =
    {
      history with
      runs =
        [ { earlier with run_id = "attempt" }; { latest with run_id = "attempt/sub" } ];
      tools = [ ("attempt/sub/item", snd (List.hd task.tools)) ];
    }
  in
  check "run origin uses longest complete run prefix"
    (contains (lines (Some overlapping)) "Source run: attempt/sub / Codex / latest-model");
  check "similar run IDs cannot claim unscoped tool origin"
    (contains
       (lines (Some { history with tools = [ ("latest-other/item", "unstructured") ] }))
       "Source run: not recorded");
  let history_rows = lines ~expanded:false (Some history) in
  let rendered_runs = List.filter (String.starts_with ~prefix:"run ") history_rows in
  check "history view names reverse chronology"
    (List.mem "RUN HISTORY / newest first" history_rows);
  check "latest record appears before previous attempts"
    (String.starts_with ~prefix:"run latest: Codex / latest-model" (List.hd rendered_runs)
    && String.starts_with ~prefix:"run earlier: Claude / old-model"
         (List.nth rendered_runs 1));
  check "latest duration and old policy remain captured"
    (contains [ List.hd rendered_runs ] "workspace-write / recorded duration 2s"
    && contains
         [ List.nth rendered_runs 1 ]
         "simulated / read-only / recorded duration 2s");
  check "display ordering leaves chronological records unchanged"
    (List.map (fun (run : run_record) -> run.run_id) history.runs
    = [ "earlier"; "latest" ]);
  let active_history =
    { history with runs = [ earlier; { latest with status = Running; ended_at = None } ] }
  in
  let active_rows =
    lines ~expanded:false (Some active_history)
    |> List.filter (String.starts_with ~prefix:"run ")
  in
  check "active latest attempt is shown first with age"
    (contains [ List.hd active_rows ] "running / live / workspace-write / run age 5s");
  let saved_history =
    { Snapshot.tasks = [ history ]; drafts = []; selected = history.id; serial = 1 }
  in
  let decoded = Result.get_ok (Snapshot.decode (Snapshot.encode saved_history)) in
  check "serialized run ordering is not reversed by Activity"
    (List.map (fun (run : run_record) -> run.run_id) (List.hd decoded.tasks).runs
    = [ "earlier"; "latest" ]);
  let plain = { task with workspace = None; tools = []; runs = [] } in
  check "unattached task does not invent workspace or tools"
    (contains (lines (Some plain)) "workspace: not attached"
    && contains (lines (Some plain)) "No tool activity yet.");
  check "task without runs has no empty run-history section"
    (not (contains (lines (Some plain)) "RUN HISTORY"));
  List.iter
    (fun width ->
      let rows = List.concat_map (Ui.wrap width) content in
      check "wrapping retains complete logical content"
        (String.concat "" rows = String.concat "" content);
      check "wrapped content fits terminal-cell width"
        (List.for_all
           (fun row -> Notty.I.width (Notty.I.string Notty.A.empty row) <= width)
           rows))
    [ 20; 36; 76; 116 ];
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.focus <- Controller.Activity;
  controller.zoom <- true;
  controller.activity_expanded <- true;
  let saved = Controller.snapshot controller in
  let render () =
    let frame = Ui.render controller ~width:120 ~height:50 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 50) frame.image;
    Buffer.contents buffer
  in
  let rendered = render () in
  check "expanded Activity exposes long metadata suffixes"
    (Controller.contains rendered "TITLE_END"
    && Controller.contains rendered "SOURCE_END"
    && Controller.contains rendered "WORKSPACE_END"
    && Controller.contains rendered "MODEL_END");
  check "expanded Activity shows exact recorded base" (Controller.contains rendered base);
  Controller.key controller (`ASCII 't', []);
  check "expanded tools remain visible after metadata wraps"
    (Controller.contains (render ()) "$ dune runtest");
  check "inspection leaves persisted state unchanged"
    (Controller.snapshot controller = saved);
  Printf.printf "Passed %d activity content checks. No commands or filesystem access.\n"
    !checks
