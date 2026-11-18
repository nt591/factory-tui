open Factory_tui

let check name condition = if not condition then failwith name

let () =
  let task =
    Model.make ~id:"confirm"
      ~title:(String.make 180 't' ^ " TITLE_END")
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
    ((not insufficient.readable) && insufficient.hits = []);
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
  List.iter
    (fun (width, height) ->
      let frame = Ui.render controller ~width ~height in
      check "resized confirmation fits terminal"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 20); (88, 13); (120, 36) ];
  Printf.printf
    "Passed complete-disclosure confirmation checks. No agent or filesystem operations.\n"
