open Factory_tui
open Model

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let row id n = (id, n)

let () =
  let viewport = Chat_viewport.create () in
  let rows = List.init 20 (fun n -> row ("message-" ^ string_of_int n) 0) in
  let update ?(task_id = "task") ?(rows = rows) ?(height = 5) ?(seek = None) distance =
    Chat_viewport.update viewport ~task_id ~rows ~height ~distance ~seek
  in
  let latest = update 0 in
  check "initial viewport follows latest"
    (latest.following && latest.offset = 15 && latest.distance = 0);
  let history = update 8 in
  check "user scroll pauses following" ((not history.following) && history.offset = 7);
  let extended = rows @ [ row "new-message" 0; row "new-message" 1 ] in
  let history = update ~rows:extended history.distance in
  check "appended output preserves top anchor"
    (history.offset = 7 && history.distance = 10);
  let history_again = update ~rows:extended history.distance in
  check "repeated renders do not move anchor" (history_again = history);
  let inserted = row "earlier" 0 :: row "earlier" 1 :: extended in
  let shifted = update ~rows:inserted history.distance in
  check "earlier stream growth preserves message identity" (shifted.offset = 9);
  let resized = update ~rows:inserted ~height:8 shifted.distance in
  check "height resize preserves history anchor when it fits" (resized.offset = 9);
  let latest = update ~rows:inserted ~height:8 0 in
  check "End resumes following" (latest.following && latest.offset = 16);
  let next = update ~rows:(inserted @ [ row "more" 0 ]) ~height:8 0 in
  check "new output stays followed after End" (next.following && next.offset = 17);
  let search = update ~rows:inserted ~seek:(Some "message-3") 0 in
  check "search seeks to message header" (search.offset = 5);
  let search_updated = update ~rows:(inserted @ [ row "append" 0 ]) search.distance in
  check "search match viewport stays anchored on append" (search_updated.offset = 5);
  Chat_viewport.reset viewport;
  let keys = [ row "a" 0; row "a" 1; row "a" 2; row "b" 0; row "b" 1; row "c" 0 ] in
  let view = update ~rows:keys ~height:2 4 in
  let view = update ~rows:keys ~height:2 (view.distance - 2) in
  check "scroll within message anchors line" (view.offset = 2);
  let shorter = [ row "a" 0; row "a" 1; row "b" 0; row "b" 1; row "c" 0 ] in
  let view = update ~rows:shorter ~height:2 view.distance in
  check "shortened stream clamps anchor to its last line" (view.offset = 1);
  let zero = update ~rows:shorter ~height:0 view.distance in
  check "zero-height render remains bounded"
    (zero.offset >= 0 && zero.offset <= List.length shorter);
  let restored = update ~rows:shorter ~height:2 view.distance in
  check "zero-height render does not discard anchor" (restored.offset = 1);
  let disappeared = List.filter (fun (id, _) -> id <> "a") shorter in
  let removed = update ~rows:disappeared ~height:2 restored.distance in
  check "removed anchor falls back within bounds"
    (removed.offset >= 0 && removed.offset <= 1);
  let following = update ~rows:disappeared ~height:2 0 in
  check "End still follows after anchor removal" following.following;
  let other = update ~task_id:"other" ~rows:keys ~height:2 0 in
  check "new task follows by default" (other.offset = 4 && other.following);
  let empty = update ~task_id:"empty" ~rows:[] ~height:5 100 in
  check "empty transcript stays bounded" (empty.offset = 0 && empty.distance = 0);
  let controller = Controller.create ~external_events:true () in
  let task =
    Result.get_ok
      (Model.start
         (Model.make ~id:"chat" ~title:"Original prompt" ~repository:"fixture")
         "run")
  in
  let messages =
    List.init 20 (fun i ->
        {
          id = Printf.sprintf "row-%d" i;
          author = "Agent";
          text = Printf.sprintf "Old message %02d" i;
          queued = false;
        })
  in
  controller.tasks <- [ { task with messages = task.messages @ messages } ];
  controller.selected <- "chat";
  controller.focus <- Controller.Conversation;
  controller.zoom <- true;
  let frame () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  ignore (frame ());
  Controller.key controller (`Home, []);
  let initial = frame () in
  check "history position is disclosed" (Controller.contains initial "reading history");
  check "Home reveals initial prompt" (Controller.contains initial "Original prompt");
  let distance = controller.scroll in
  let saved = Controller.snapshot controller in
  Controller.receive controller
    {
      task_id = "chat";
      run_id = "run";
      event = Message ("latest", "New streamed message");
    };
  let updated = frame () in
  check "stream does not displace history"
    (Controller.contains updated "Original prompt"
    && not (Controller.contains updated "New streamed message"));
  check "bottom distance grows to retain history" (controller.scroll > distance);
  check "streamed update still changes persisted task content"
    (Controller.snapshot controller <> saved);
  let saved = Controller.snapshot controller in
  ignore (frame ());
  ignore (frame ());
  check "repeated viewport layout leaves snapshots unchanged"
    (Controller.snapshot controller = saved);
  Controller.key controller (`End, []);
  let current = frame () in
  check "End shows new stream"
    (controller.scroll = 0 && Controller.contains current "New streamed message");
  check "End removes paused label" (not (Controller.contains current "reading history"));
  Controller.receive controller
    {
      task_id = "chat";
      run_id = "run";
      event = Message ("another", "Another streamed message");
    };
  check "following continues on later output"
    (Controller.contains (frame ()) "Another streamed message");
  Controller.act controller Controller.Begin_chat_search;
  Controller.set_input controller "Old message 03";
  Controller.submit controller;
  check "search positions old message" (Controller.contains (frame ()) "Old message 03");
  let offset = controller.scroll in
  Controller.receive controller
    { task_id = "chat"; run_id = "run"; event = Message ("growth", String.make 180 'x') };
  check "search anchor stays visible while output arrives"
    (Controller.contains (frame ()) "Old message 03" && controller.scroll > offset);
  Controller.act controller (Controller.Select "chat");
  check "explicit card selection follows newest" (controller.scroll = 0);
  Printf.printf "Passed %d chat viewport checks. No processes or database access.\n"
    !checks
