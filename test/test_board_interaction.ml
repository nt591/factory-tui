open Factory_tui
open Model
open Controller

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ctrl_x t = Controller.key t (`ASCII 'X', [ `Ctrl ])

let () =
  let t = Controller.create ~external_events:true () in
  let idle = Model.make ~id:"idle" ~title:"Not running yet" ~repository:"fixture" in
  let running = Result.get_ok (Model.start ~simulated:true idle "run") in
  let running = { running with id = "running" } in
  t.tasks <- [ idle; running ];
  t.selected <- idle.id;
  let snapshot = Controller.snapshot t in
  let frame = Ui.render t ~width:120 ~height:36 in
  let lane_states =
    List.map (fun (_, state, _, _) -> state) frame.columns |> List.sort_uniq compare
  in
  check "there is no Queued lane"
    (List.length lane_states = 3 && not (List.mem Queued lane_states));
  check "unstarted and running tasks share Working"
    (Board_lanes.contains Working idle && Board_lanes.contains Working running);
  check "unstarted task metadata does not claim execution"
    (Task_attention.card_text ~updates:0 idle = "Not started");
  check "rendering does not promote saved work to running"
    (Controller.snapshot t = snapshot && idle.active = None);
  check "starting a task preserves its lane"
    (Board_lanes.of_state idle.state = Board_lanes.of_state running.state);
  Controller.key t (`Enter, []);
  check "task entry edits by default" (t.input = Compose && t.zoom);
  Controller.set_input t "Keep sent messages safe";
  let before = Option.get (Controller.selected t) in
  ctrl_x t;
  check "Ctrl-X clears editor and draft without changing task history"
    (t.input = Compose
    && Controller.draft t = ""
    && Text_edit.text t.editor = ""
    && Controller.selected t = Some before
    && t.deletion = None);
  Controller.set_input t "Preserve draft on escape";
  Controller.key t (`Tab, [ `Shift ]);
  check "Shift-Tab switches from editing to Activity"
    (t.focus = Activity && t.input = Normal && t.zoom);
  Controller.key t (`Tab, []);
  check "Tab returns to Conversation without a board round trip"
    (t.focus = Conversation && t.input = Normal && t.zoom);
  ctrl_x t;
  check "Ctrl-X in conversation navigation also clears only draft"
    (Controller.draft t = "" && t.deletion = None && Controller.selected t = Some before);
  Controller.act t Begin_compose;
  Controller.set_input t "Saved on escape";
  Controller.key t (`Escape, []);
  check "one Escape returns from INSERT to visible Board"
    (t.focus = Board && (not t.zoom) && t.input = Normal
    && Controller.draft t = "Saved on escape");
  Controller.act t (Focus Activity);
  Controller.act t Zoom;
  Controller.key t (`Escape, []);
  check "one Escape returns from expanded Activity to Board"
    (t.focus = Board && (not t.zoom) && not t.activity_expanded);
  Controller.act t (Focus Conversation);
  Controller.act t Begin_delete;
  check "task view cannot open task deletion" (t.deletion = None);
  Controller.act t (Focus Board);
  ctrl_x t;
  check "board Ctrl-X opens deletion without clearing draft"
    (t.deletion <> None && Controller.draft t = "Saved on escape");
  Controller.paste_key t (`ASCII 'y', []);
  Controller.key t (`Enter, []);
  check "pasted y and Enter cannot confirm"
    (t.tasks = [ idle; running ] && t.deletion <> None);
  Controller.key t (`ASCII 'n', []);
  check "n cancels without changes" (t.deletion = None && t.tasks = [ idle; running ]);
  ctrl_x t;
  Controller.key t (`ASCII 'Y', [ `Shift ]);
  check "Y confirms task deletion on Board"
    (t.tasks = [ running ] && t.selected = running.id);
  check "confirmation leaves the other task running"
    ((List.hd t.tasks).active = running.active);
  Printf.printf
    "Passed %d board/task context checks. Pure state and rendering; no agents.\n" !checks
