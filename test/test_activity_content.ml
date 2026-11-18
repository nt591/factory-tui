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
    Activity_content.lines ~expanded ~raw ~waiting task
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
  check "waiting status is explicit"
    (contains
       (lines ~waiting:true (Some task))
       "Waiting for previous workspace process cleanup.");
  check "run history keeps captured model and write policy"
    (contains content
       "run run: Codex / recorded-model / completed / live / workspace-write");
  let plain = { task with workspace = None; tools = []; runs = [] } in
  check "unattached task does not invent workspace or tools"
    (contains (lines (Some plain)) "workspace: not attached"
    && contains (lines (Some plain)) "No tool activity yet.");
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
