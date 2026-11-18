open Factory_tui

let check name condition = if not condition then failwith name

let () =
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"task" ~title:"History prompt" ~repository:"fixture" in
  let messages =
    List.init 50 (fun i ->
        {
          Model.id = string_of_int i;
          author = "Codex";
          text = Printf.sprintf "History %02d" i;
          queued = false;
        })
  in
  let tool =
    Yojson.Basic.to_string
      (`Assoc
         [
           ("type", `String "command_execution");
           ("command", `String "fixture");
           ( "aggregated_output",
             `String (String.concat "\n" (List.init 60 (Printf.sprintf "Tool row %02d")))
           );
           ("status", `String "completed");
         ])
  in
  controller.tasks <-
    [ { task with messages = task.messages @ messages; tools = [ ("tool", tool) ] } ];
  controller.selected <- task.id;
  controller.zoom <- true;
  controller.tools_expanded <- true;
  controller.focus <- Controller.Conversation;
  let render () = Ui.render controller ~width:120 ~height:36 in
  ignore (render ());
  Controller.key controller (`Home, []);
  let frame = render () in
  let distance = controller.scroll in
  check "fixture starts in old chat history" (distance > 3);
  let activity, _ =
    List.find (fun (_, focus) -> focus = Controller.Activity) frame.panes
  in
  let chat, _ =
    List.find (fun (_, focus) -> focus = Controller.Conversation) frame.panes
  in
  let saved = Controller.snapshot controller in
  Ui.mouse controller frame ~now:1.
    (`Press (`Scroll `Down), (activity.x + 2, activity.y + 2), []);
  check "activity starts at its own offset not chat history" (controller.scroll = 3);
  let frame = render () in
  check "chat distance retained while Activity renders"
    (Pane_scroll.position controller.pane_scroll Chat = distance);
  Ui.mouse controller frame ~now:2. (`Press (`Scroll `Down), (chat.x + 2, chat.y + 2), []);
  check "returning chat applies wheel to its saved history offset"
    (controller.scroll = distance - 3);
  let frame = render () in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  let rows = String.split_on_char '\n' (Buffer.contents buffer) in
  check "unfocused Activity retains its visible starting row"
    (Controller.contains (List.nth rows (activity.y + 1)) "run: idle");
  check "unfocused Activity retains its remembered offset"
    (Pane_scroll.position controller.pane_scroll Activity = 3);
  Controller.act controller (Controller.Focus Controller.Activity);
  check "activity restores its last offset" (controller.scroll = 3);
  Controller.act controller (Controller.Focus Controller.Conversation);
  check "direct focus restores chat history" (controller.scroll = distance - 3);
  check "pane positions are not persisted" (Controller.snapshot controller = saved);
  Controller.act controller (Controller.Focus Controller.Activity);
  Controller.key controller (`ASCII 'G', []);
  ignore (render ());
  let bottom = controller.scroll in
  check "tool history reaches its final visible window" (bottom > 3);
  Controller.act controller (Controller.Focus Controller.Conversation);
  ignore (render ());
  check "reading chat does not reset visible tool history"
    (Pane_scroll.position controller.pane_scroll Activity = bottom);
  let smaller = Ui.render controller ~width:120 ~height:24 in
  check "resize clamps background Activity without rewriting snapshots"
    (Pane_scroll.position controller.pane_scroll Activity >= 0
    && Controller.snapshot controller = saved
    && Notty.I.height smaller.image = 24);

  Controller.act controller (Controller.Focus Controller.Conversation);
  controller.zoom <- false;
  ignore (render ());
  Controller.key controller (`Home, []);
  let frame = render () in
  let history = Pane_scroll.position controller.pane_scroll Chat in
  let queued, _, _, _ =
    List.find (fun (_, state, _, _) -> state = Model.Queued) frame.columns
  in
  Ui.mouse controller frame ~now:3.
    (`Press (`Scroll `Down), (queued.x + 2, queued.y + 2), []);
  check "column wheel focuses board without changing selected task"
    (controller.focus = Controller.Board && controller.selected = task.id);
  let frame = render () in
  check "board focus keeps remembered paused chat history"
    (Pane_scroll.position controller.pane_scroll Chat = history && controller.scroll = 0);
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "board-focused frame still discloses paused history"
    (Controller.contains (Buffer.contents buffer) "reading history");
  Controller.act controller (Controller.Focus Controller.Conversation);
  check "returning from board restores history distance" (controller.scroll = history);
  check "board wheel changes no saved task data" (Controller.snapshot controller = saved);
  controller.zoom <- true;
  Controller.act controller (Controller.Focus Controller.Activity);
  controller.activity_expanded <- true;
  let remembered = Pane_scroll.position controller.pane_scroll Activity in
  ignore (Ui.render controller ~width:120 ~height:8);
  check "zero-height Activity content does not discard remembered position"
    (Pane_scroll.position controller.pane_scroll Activity = remembered
    && controller.scroll = remembered);
  controller.activity_expanded <- false;
  Controller.act controller (Controller.Select task.id);
  check "explicit task selection clears detail offsets"
    (controller.scroll = 0
    && Pane_scroll.position controller.pane_scroll Chat = 0
    && Pane_scroll.position controller.pane_scroll Activity = 0);
  Controller.key controller (`Tab, []);
  check "keyboard pane cycling retains fresh-position behavior" (controller.scroll = 0);
  Printf.printf "Passed separate detail-pane scroll checks. Pure frame/input data only.\n"
