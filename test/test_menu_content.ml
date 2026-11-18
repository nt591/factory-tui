open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let contains rows value = Controller.contains (String.concat "\n" rows) value

let () =
  let task = Model.make ~id:"fixture" ~title:"Inspect settings" ~repository:"fixture" in
  let settings mode task =
    Menu_content.settings ~mode ~database:(Some "/fixture/board.sqlite") ~task
  in
  List.iter
    (fun policy ->
      let mode = Menu_content.Live policy in
      let help = Menu_content.help ~mode in
      let content = settings mode (Some task) in
      check "live help explains supported harness"
        (contains help "Live execution supports Codex only");
      check "live help does not advertise simulated harness cycling"
        (not (contains help "H cycles"));
      check "live help requires explicit confirmation"
        (contains help "s asks for live confirmation");
      check "live help does not advertise demo pause" (not (contains help "f pauses"));
      check "live settings edits model without claiming harness support"
        (contains content "m edits model / live Codex only"
        && not (contains content "H changes harness"));
      check "live settings retain selected model and storage"
        (contains content "Model: coding-large"
        && contains content "/fixture/board.sqlite");
      check "live settings state captured launch policy"
        (contains content
           (match policy with
           | Read_only -> "Read-only"
           | Workspace_write -> "Workspace-write")))
    [ Read_only; Workspace_write ];
  let replay = Menu_content.help ~mode:Menu_content.Replay in
  check "replay help refuses starting a run" (contains replay "s cannot start a run");
  check "replay settings distinguish supplied updates"
    (contains (settings Replay (Some task)) "no process can start from this mode");
  check "fake help starts fixture not model"
    (contains (Menu_content.help ~mode:Fake) "s starts a local process fixture");
  check "fake settings retain no-model disclosure"
    (contains (settings Fake (Some task)) "No model calls");
  check "simulation help identifies simulated selection and pause"
    (contains (Menu_content.help ~mode:Simulation) "H cycles simulated"
    && contains (Menu_content.help ~mode:Simulation) "f pauses demo");
  check "simulation settings are not agent access"
    (contains (settings Simulation (Some task)) "no model or agent process starts");
  let accepted = { task with state = Done } in
  List.iter
    (fun mode ->
      let content = settings mode (Some accepted) in
      check "accepted settings are read-only in every mode"
        (contains content "settings are read-only"
        && not (contains content "m edits model")))
    [ Simulation; Replay; Fake; Live Read_only ];
  check "no selected task offers selection guidance"
    (contains (settings Simulation None) "Select a task first");
  let live =
    Result.get_ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None)
  in
  let controller = Controller.create () in
  controller.database_path <- Some "/fixture/board.sqlite";
  Result.get_ok (Controller.initialize_board controller ~saved:None ~live:(Some live));
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  Controller.act controller Controller.Help;
  let before = Controller.snapshot controller in
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  check "actual live help renders mode-correct harness guidance"
    (Controller.contains (render ()) "Live execution supports Codex only");
  Controller.key controller (`Tab, []);
  Controller.key controller (`End, []);
  let content = render () in
  check "actual live settings omits misleading cycle guidance"
    (Controller.contains content "live Codex only"
    && not (Controller.contains content "H changes harness"));
  check "menu content creates no live confirmation"
    (controller.live_confirmation = None && Controller.snapshot controller = before);
  Controller.key controller (`ASCII 'H', []);
  check "live Settings shortcut cannot select unsupported harness"
    (Controller.snapshot controller = before && controller.live_confirmation = None);
  Controller.key controller (`Escape, []);
  Controller.key controller (`ASCII 'H', []);
  check "normal live shortcut preserves Codex and captured settings"
    (Controller.snapshot controller = before
    && Controller.contains controller.status "supports Codex only");
  controller.tasks <- [ { task with harness = Claude } ];
  Controller.key controller (`ASCII 'H', []);
  check "explicit live shortcut can repair imported simulated harness"
    ((Option.get (Controller.selected controller)).harness = Codex
    && (Option.get (Controller.selected controller)).runs = []
    && controller.live_confirmation = None);
  controller.tasks <- [ accepted ];
  let accepted_snapshot = Controller.snapshot controller in
  Controller.key controller (`ASCII 'm', []);
  check "accepted task cannot open an unsavable model editor"
    (controller.input = Controller.Normal
    && Controller.snapshot controller = accepted_snapshot);
  Controller.key controller (`ASCII 'H', []);
  check "accepted task cannot repair or cycle harness"
    (Controller.snapshot controller = accepted_snapshot);
  Controller.act controller Controller.Help;
  Controller.key controller (`Tab, []);
  Controller.key controller (`ASCII 'm', []);
  check "accepted Settings model shortcut also refuses editing"
    (controller.input = Controller.Normal
    && Controller.snapshot controller = accepted_snapshot);
  let demo = Controller.create ~external_events:true () in
  demo.tasks <- [ task ];
  demo.selected <- task.id;
  Controller.key demo (`ASCII 'H', []);
  check "simulation still permits harness cycling"
    ((Option.get (Controller.selected demo)).harness = Claude);
  Printf.printf "Passed %d menu content checks. Pure modes and rendering only.\n" !checks
