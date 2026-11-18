open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let task = Model.make ~id:"composer" ~title:"Instruction" ~repository:"fixture"

let () =
  List.iter
    (fun policy ->
      let text =
        Composer_guidance.text ~mode:(Menu_content.Live policy) ~editing:false task
      in
      check "live composer names supported harness instead of cycling"
        (Controller.contains text "live Codex only"
        && not (Controller.contains text "H harness"));
      let imported =
        Composer_guidance.text ~mode:(Menu_content.Live policy) ~editing:false
          { task with harness = Claude }
      in
      check "imported Claude composer offers explicit recovery to Codex"
        (Controller.contains imported "H selects Codex");
      let editing =
        Composer_guidance.text ~mode:(Menu_content.Live policy) ~editing:true task
      in
      check "editing uses queue instructions not steer/send-now claims"
        (Controller.contains editing "Enter queues"
        && Controller.contains editing "Ctrl-L newline"))
    [ Read_only; Workspace_write ];
  List.iter
    (fun mode ->
      check "nonlive composer retains simulated harness controls"
        (Controller.contains
           (Composer_guidance.text ~mode ~editing:false task)
           "H harness");
      check "accepted composer never offers editing"
        (Composer_guidance.text ~mode ~editing:false { task with state = Done }
        = "Accepted / read-only"))
    [ Menu_content.Simulation; Fake; Replay ];
  let controller = Controller.create () in
  controller.schedules <- [];
  controller.database_path <- Some "/fixture/db";
  let config =
    Result.get_ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None)
  in
  Result.get_ok (Controller.enable_live controller config);
  let workspace =
    {
      source = "/fixture/source";
      directory = "/fixture/task";
      base = String.make 40 'a';
      name = "fixture";
    }
  in
  let prepared = { task with workspace = Some workspace } in
  let working = Result.get_ok (Model.start ~simulated:false prepared "active-run") in
  controller.tasks <- [ working ];
  controller.selected <- working.id;
  controller.zoom <- true;
  controller.focus <- Controller.Conversation;
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  let saved = Controller.snapshot controller in
  check "actual live composer renders supported controls"
    (Controller.contains (render ()) "m model / live Codex only"
    && not (Controller.contains (render ()) "H harness"));
  check "guidance starts no additional run or confirmation"
    (Controller.snapshot controller = saved && controller.live_confirmation = None);
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "Follow-up for the next turn";
  check "working composer still displays explicit queue instruction"
    (Controller.contains (render ()) "Enter queues");
  Controller.key controller (`Enter, []);
  let updated = Option.get (Controller.selected controller) in
  check "reply during work stays queued under same active run"
    ((List.hd (List.rev updated.messages)).queued
    && updated.active = working.active
    && updated.runs = working.runs && updated.state = Working);
  check "submission does not trigger live confirmation"
    (controller.live_confirmation = None);
  Printf.printf "Passed %d mode-aware composer checks. Pure copy/controller only.\n"
    !checks
