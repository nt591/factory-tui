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
  ignore (render ());
  Controller.act controller (Controller.Focus Controller.Activity);
  check "activity restores its last offset" (controller.scroll = 3);
  Controller.act controller (Controller.Focus Controller.Conversation);
  check "direct focus restores chat history" (controller.scroll = distance - 3);
  check "pane positions are not persisted" (Controller.snapshot controller = saved);
  Controller.act controller (Controller.Select task.id);
  check "explicit task selection clears detail offsets"
    (controller.scroll = 0
    && Pane_scroll.position controller.pane_scroll Chat = 0
    && Pane_scroll.position controller.pane_scroll Activity = 0);
  Controller.key controller (`Tab, []);
  check "keyboard pane cycling retains fresh-position behavior" (controller.scroll = 0);
  Printf.printf "Passed separate detail-pane scroll checks. Pure frame/input data only.\n"
