open Factory_tui
open Controller

let check name value = if not value then failwith name

let () =
  let t = Controller.create ~external_events:true () in
  let task = Model.make ~id:"task" ~title:"Talk to agent" ~repository:"fixture" in
  t.tasks <- [ task ];
  t.selected <- task.id;
  t.drafts <- [ (task.id, "Keep my reply") ];
  let saved = Controller.snapshot t in
  Controller.key t (`Enter, []);
  check "board Enter opens expanded conversation in insert mode"
    (t.zoom && t.focus = Conversation && t.input = Compose);
  Controller.key t (`Escape, []);
  check "first Escape leaves editing without hiding conversation"
    (t.zoom && t.focus = Conversation && t.input = Normal);
  Controller.key t (`ASCII 'e', []);
  Controller.key t (`ASCII 'e', []);
  check "e never collapses an expanded conversation" (t.zoom && t.focus = Conversation);
  Controller.key t (`Enter, []);
  check "conversation Enter resumes reply editing, not the board"
    (t.zoom && t.focus = Conversation && t.input = Compose);
  Controller.key t (`Tab, []);
  check "Tab leaves editor and moves to Activity" (t.input = Normal && t.focus = Activity);
  Controller.act t (Focus Conversation);
  Controller.key t (`Escape, []);
  check "Escape from expanded chat returns visible board focus"
    ((not t.zoom) && t.focus = Board);
  Controller.act t (Focus Conversation);
  Controller.key t (`Escape, []);
  check "Escape from split conversation focuses board" ((not t.zoom) && t.focus = Board);
  Controller.key t (`Tab, []);
  check "Tab into conversation retains read/navigation mode"
    (t.focus = Conversation && t.input = Normal);
  Controller.key t (`Enter, []);
  check "split conversation Enter only opens editor"
    ((not t.zoom) && t.focus = Conversation && t.input = Compose);
  check "entry and layer navigation preserve drafts and start no run"
    (Controller.snapshot t = saved && (Option.get (Controller.selected t)).active = None);
  Controller.key t (`Escape, []);
  t.tasks <- [ { task with state = Model.Done } ];
  Controller.act t (Focus Board);
  Controller.key t (`Enter, []);
  check "archived task opens read-only conversation"
    (t.zoom && t.focus = Conversation && t.input = Normal);
  Printf.printf "Passed conversation entry and Escape-layer checks. Pure input/state.\n"
