open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let controller = Controller.create ~external_events:true () in
  let task =
    Result.get_ok
      (start (make ~id:"reply" ~title:"Original instruction" ~repository:"fixture") "run")
  in
  let messages =
    List.init 40 (fun index ->
        {
          id = string_of_int index;
          author = "Agent";
          text = Printf.sprintf "History %02d" index;
          queued = false;
        })
  in
  controller.tasks <-
    [
      {
        task with
        title =
          String.concat "\n" (List.init 60 (Printf.sprintf "Activity metadata %02d"));
        messages = task.messages @ messages;
      };
    ];
  controller.selected <- task.id;
  Controller.act controller Zoom;
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  ignore (render ());
  Controller.key controller (`Home, []);
  ignore (render ());
  check "fixture starts paused in history" (controller.scroll > 0);
  Pane_scroll.remember controller.pane_scroll Activity 3;
  let runs = (Option.get (Controller.selected controller)).runs in
  Controller.act controller Begin_compose;
  Controller.set_input controller "New queued reply visible now";
  Controller.submit controller;
  let text = render () in
  check "successful submission makes queued reply immediately visible"
    (Controller.contains text "New queued reply visible now"
    && controller.scroll = 0
    && not (Controller.contains text "reading history"));
  check "submission does not start or steer active run"
    ((Option.get (Controller.selected controller)).runs = runs
    && (Option.get (Controller.selected controller)).active = task.active);
  check "submission retains Activity reading memory"
    (Pane_scroll.position controller.pane_scroll Activity = 3);
  Controller.act controller Begin_chat_search;
  Controller.set_input controller "History 03";
  Controller.submit controller;
  ignore (render ());
  check "old search match pauses reading" (controller.scroll > 0);
  Controller.act controller Begin_compose;
  Controller.set_input controller "Reply after searching older history";
  Controller.submit controller;
  check "search seek cannot pull submitted reply back out of view"
    (Controller.contains (render ()) "Reply after searching older history"
    && controller.scroll = 0
    && Chat_search.query controller.chat_search = "History 03");
  Controller.key controller (`Home, []);
  ignore (render ());
  let paused = controller.scroll in
  Controller.act controller Begin_compose;
  Controller.set_input controller "   ";
  Controller.submit controller;
  ignore (render ());
  check "failed empty submission keeps editor and paused anchor"
    (controller.input = Compose && controller.scroll = paused
    && Controller.draft controller = "   ");
  let before = Controller.snapshot controller in
  Controller.key controller (`Escape, []);
  ignore (render ());
  check "leaving an unsent draft does not resume following"
    (controller.focus = Board && controller.input = Normal
    && Controller.snapshot controller = before
    && Pane_scroll.position controller.pane_scroll Chat > 0);
  Printf.printf "Passed %d queued-reply visibility checks. Pure input/rendering only.\n"
    !checks
