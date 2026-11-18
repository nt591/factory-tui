open Factory_tui

let check name condition = if not condition then failwith name

let () =
  let task =
    Model.make ~id:"confirm"
      ~title:(String.make 980 't' ^ " TITLE_END")
      ~repository:"fixture"
  in
  let task =
    {
      task with
      model = String.make 120 'm' ^ "MODEL_END";
      thread_id = Some (String.make 80 'a' ^ "THREAD_END");
      workspace =
        Some
          {
            source = "/source";
            directory = "/work/" ^ String.make 140 'w' ^ "/PATH_END";
            base = String.make 40 'a';
            name = "fixture";
          };
    }
  in
  let task = Some task in
  let height = Live_confirmation.required_height task ~width:88 in
  check "long details need more than fixed minimum" (height > 13);
  let insufficient = Live_confirmation.render task ~width:88 ~height:13 in
  check "hidden details cannot expose Run"
    ((not insufficient.readable)
    && not
         (List.exists
            (fun (hit : Live_confirmation.hit) -> hit.action = Live_confirmation.Run)
            insufficient.hits));
  let view = Live_confirmation.render task ~width:88 ~height in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (88, height) view.image;
  let text = Buffer.contents buffer in
  check "expanded disclosure exposes all identity suffixes"
    (view.readable
    && List.for_all (Controller.contains text)
         [ "TITLE_END"; "MODEL_END"; "THREAD_END"; "PATH_END" ]);
  let run =
    List.find
      (fun (hit : Live_confirmation.hit) -> hit.action = Live_confirmation.Run)
      view.hits
  in
  let row = List.nth (String.split_on_char '\n' text) run.y in
  check "Run target tracks actual button row"
    (Controller.contains row "[Run / Enter or y]");
  check "confirmation frame and targets remain bounded"
    (Notty.I.height view.image = height
    && List.for_all
         (fun (h : Live_confirmation.hit) -> h.y < height - 1 && h.x + h.width <= 88)
         view.hits);
  let viewport = Live_confirmation.create () in
  let render () = Live_confirmation.render ~viewport task ~width:88 ~height:13 in
  let first = render () in
  check "scrollable details expose a content viewport" (first.content_rows = 9);
  Live_confirmation.key viewport (`End, []);
  let bottom = render () in
  check "jumping to bottom does not skip disclosure review" (not bottom.readable);
  Live_confirmation.key viewport (`Home, []);
  ignore (render ());
  for _ = 1 to height do
    Live_confirmation.key viewport (`ASCII 'j', []);
    ignore (render ())
  done;
  let reviewed = render () in
  check "scrolling through all rows unlocks Run" reviewed.readable;
  let buffer = Buffer.create 4096 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (88, 13) reviewed.image;
  check "last page shows thread suffix and Run"
    (Controller.contains (Buffer.contents buffer) "THREAD_END"
    && Controller.contains (Buffer.contents buffer) "[Run / Enter or y]");
  check "authorization checks the current disclosure"
    (Live_confirmation.can_confirm viewport ~policy:Model.Read_only task
    && (not (Live_confirmation.can_confirm viewport ~policy:Model.Workspace_write task))
    && not
         (Live_confirmation.can_confirm viewport ~policy:Model.Read_only
            (Some { (Option.get task) with title = "changed" })));
  Live_confirmation.reset viewport;
  ignore (render ());
  check "each dialog needs its own review" (not (render ()).readable);
  for _ = 1 to height do
    Live_confirmation.key viewport (`ASCII 'f', [ `Ctrl ]);
    ignore (render ())
  done;
  check "viewport-sized pages cover every row" (render ()).readable;
  let changed = Some { (Option.get task) with model = "replacement model" } in
  check "changed run details reset disclosure coverage"
    (not (Live_confirmation.render ~viewport changed ~width:88 ~height:13).readable);
  check "resizing clears prior row coverage"
    (not (Live_confirmation.render ~viewport task ~width:70 ~height:13).readable);
  let exact = Live_confirmation.create () in
  let sanitized = Some { (Option.get task) with title = "title with\nspace" } in
  ignore (Live_confirmation.render ~viewport:exact sanitized ~width:88 ~height:40);
  check "sanitized display does not equate different raw task details"
    (not
       (Live_confirmation.can_confirm exact ~policy:Model.Read_only
          (Some { (Option.get sanitized) with title = "title with space" })));
  let unsafe = Some { (Option.get task) with title = "Task\255\027\194\128" } in
  ignore (Live_confirmation.render unsafe ~width:88 ~height:40);
  check "malformed title and controls cannot break rendering" true;
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ Option.get task ];
  controller.selected <- "confirm";
  controller.live_confirmation <- Some "confirm";
  ignore (Ui.render controller ~width:88 ~height:13);
  Controller.key controller (`ASCII 'y', []);
  check "TUI refuses clipped confirmation"
    ((Option.get (Controller.selected controller)).active = None
    && controller.live_confirmation <> None);
  let before = (Option.get (Controller.selected controller)).runs in
  let frame = Ui.render controller ~width:88 ~height:13 in
  let body = Option.get frame.modal_scroll in
  Ui.mouse controller frame ~now:0. (`Press (`Scroll `Down), (body.x, body.y), []);
  ignore (Ui.render controller ~width:88 ~height:13);
  Controller.key controller (`ASCII 'y', [ `Ctrl ]);
  check "modified confirmation keys cannot authorize"
    ((Option.get (Controller.selected controller)).runs = before);
  for _ = 1 to height do
    Controller.key controller (`ASCII 'f', [ `Ctrl ]);
    ignore (Ui.render controller ~width:88 ~height:13)
  done;
  check "controller scrolling unlocks complete disclosure"
    controller.confirmation_readable;
  let frame = Ui.render controller ~width:88 ~height:13 in
  let run =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Confirm_live) frame.hits
  in
  let offset = run.rect.y in
  let buffer = Buffer.create 4096 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (88, 13) frame.image;
  check "scrolled controller Run hit aligns with button"
    (Controller.contains
       (List.nth (String.split_on_char '\n' (Buffer.contents buffer)) offset)
       "[Run / Enter or y]");
  List.iter
    (fun (width, height) ->
      let frame = Ui.render controller ~width ~height in
      check "resized confirmation fits terminal"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 20); (88, 13); (120, 36) ];
  Printf.printf
    "Passed complete-disclosure confirmation checks. No agent or filesystem operations.\n"
