open Factory_tui
open Model

let check name condition = if not condition then failwith name
let has source text = Controller.contains source text
let task = Model.make ~id:"selected" ~title:"Instruction" ~repository:"fixture"

let () =
  let text ?(live = false) ?(replay = false) task =
    Task_guidance.selection ~live ~replay task
  in
  check "selection guidance identifies task"
    (String.starts_with ~prefix:"selected / " (text task));
  check "queued fixture guidance does not claim live execution"
    (has (text task) "fixture run");
  check "unattached live task points to workspace setup"
    (has (text ~live:true task) "require a workspace");
  let workspace =
    {
      source = "/fixture/source";
      directory = "/fixture/task";
      base = String.make 40 'a';
      name = "fixture";
    }
  in
  let attached = { task with workspace = Some workspace } in
  check "live queued task requires confirmation"
    (has (text ~live:true attached) "s opens live confirmation");
  check "unsupported live harness offers explicit repair"
    (has (text ~live:true { attached with harness = Claude }) "H selects Codex");
  check "empty queue requires new instruction"
    (has (text { task with messages = [] }) "i queues an instruction");
  check "Ready offers acceptance without merging"
    (has (text { task with state = Ready }) "a accepts without merging");
  check "Working explains queued reply and stop"
    (has (text { task with state = Working }) "x stops");
  check "Done is explicitly read-only"
    (has (text { task with state = Done }) "Chat is read-only");
  List.iter
    (fun state ->
      check "replay never offers process Start"
        (has (text ~replay:true { task with state }) "no process can start"))
    [ Queued; Working; Needs_you ];
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ task; { task with id = "other"; state = Ready } ];
  controller.selected <- task.id;
  controller.status <- "Task accepted. Chat is read-only.";
  Controller.act controller (Controller.Select "other");
  check "explicit selection replaces stale previous-task footer"
    (has controller.status "other / Ready for review");
  Controller.key controller (`ASCII 'h', []);
  check "keyboard selection refreshes footer identity"
    (has controller.status "selected / Replay controls updates");
  controller.status <- "Storage error: checkpoint failed";
  Controller.act controller (Controller.Select "other");
  check "selection never masks a storage error"
    (controller.status = "Storage error: checkpoint failed");
  check "selection starts no run"
    (List.for_all
       (fun (task : task) -> task.active = None && task.runs = [])
       controller.tasks);
  Printf.printf "Passed task selection guidance checks. Pure copy/state only.\n"
