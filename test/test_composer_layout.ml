open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let contains rows text = Controller.contains (String.concat "\n" rows) text

let () =
  let text = String.concat "\n" (List.init 12 (Printf.sprintf "draft line %02d")) in
  let editor = Text_edit.create text in
  let layout editor =
    Composer_layout.make ~width:40 ~capacity:3 ~preview:"ignored" ~editor:(Some editor)
  in
  let bottom = layout editor in
  check "ending cursor window follows final lines"
    (bottom.first = 10 && bottom.last = 12 && bottom.total = 12 && bottom.above
   && not bottom.below);
  check "last draft line and cursor stay visible" (contains bottom.rows "draft line 11▏");
  check "border reports rows above"
    (Composer_layout.position ~width:40 bottom = "draft rows 10-12/12 ↑");
  let rec move count fn value =
    if count <= 0 then value else move (count - 1) fn (fn value)
  in
  let top_editor = move 20 Text_edit.up editor |> Text_edit.home in
  let top = layout top_editor in
  check "first cursor exposes following rows"
    (top.first = 1 && top.last = 3 && (not top.above) && top.below
    && contains top.rows "> ▏draft line 00");
  let middle = layout (move 6 Text_edit.down top_editor) in
  check "middle cursor discloses both overflow directions"
    (middle.above && middle.below && middle.first = 5 && middle.last = 7);
  let full =
    Composer_layout.make ~width:40 ~capacity:20 ~preview:"" ~editor:(Some editor)
  in
  check "fitting draft has no overflow footer"
    (Composer_layout.position ~width:40 full = "" && List.length full.rows = 12);
  let preview = Composer_layout.make ~width:40 ~capacity:3 ~preview:text ~editor:None in
  check "saved draft preview shows last rows without editing cursor"
    (preview.first = 10
    && contains preview.rows "draft line 11"
    && not (contains preview.rows "▏"));
  let empty =
    Composer_layout.make ~width:40 ~capacity:3 ~preview:"Write reply"
      ~editor:(Some (Text_edit.create ""))
  in
  check "empty editing prompt does not display placeholder"
    (empty.rows = [ "> ▏" ] && empty.total = 1);
  let invalid =
    Composer_layout.make ~width:40 ~capacity:3 ~preview:"bad\255\027\194\128\nline"
      ~editor:None
  in
  check "unsafe preview is sanitized for terminal only"
    (invalid.rows = [ "  bad�  "; "line" ]);
  List.iter
    (fun width ->
      let editor = Text_edit.create ("start " ^ String.make 180 'x' ^ " end 👩🏽‍💻 é") in
      let window =
        Composer_layout.make ~width ~capacity:3 ~preview:"" ~editor:(Some editor)
      in
      check "wrapped editing keeps complete cursor row" (contains window.rows "▏");
      check "window size is bounded"
        (List.length window.rows <= 3 && window.last <= window.total);
      check "footer fits its available width"
        (Notty.I.width
           (Notty.I.string Notty.A.empty (Composer_layout.position ~width window))
        <= width);
      check "layout does not alter editor text"
        (String.ends_with ~suffix:"👩🏽‍💻 é" (Text_edit.text editor)))
    [ 1; 2; 20; 40; 76 ];
  let zero = Composer_layout.make ~width:0 ~capacity:0 ~preview:text ~editor:None in
  check "hidden composer has no rows or footer"
    (zero.rows = [] && Composer_layout.position ~width:40 zero = "");
  let controller = Controller.create ~external_events:true () in
  Controller.act controller (Controller.Focus Conversation);
  Controller.act controller Controller.Zoom;
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller text;
  let before = Controller.snapshot controller in
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, bottom_text = render 120 36 in
  check "UI reports long draft range"
    (Controller.contains bottom_text "draft rows 8-12/12");
  for _ = 1 to 20 do
    Controller.key controller (`Arrow `Up, [])
  done;
  Controller.key controller (`Home, []);
  let _, top_text = render 120 36 in
  check "UI cursor movement shows top range"
    (Controller.contains top_text "draft rows 1-5/12");
  check "render and cursor movement preserve saved draft"
    (Controller.snapshot controller = before);
  List.iter
    (fun (width, height) ->
      let frame, _ = render width height in
      check "composer frames stay terminal-sized"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 23); (120, 36); (180, 50) ];
  Controller.submit controller;
  check "submitted long draft is exact"
    (List.exists
       (fun (message : Model.message) -> message.text = text && message.queued)
       (Option.get (Controller.selected controller)).messages);
  let accepted =
    {
      (Option.get (Controller.selected controller)) with
      state = Model.Done;
      active = None;
    }
  in
  controller.tasks <- [ accepted ];
  controller.input <- Controller.Compose;
  controller.editor <- Text_edit.create "must not appear";
  let frame, accepted_text = render 120 36 in
  let accepted_body =
    String.concat "\n"
      (List.filteri (fun index _ -> index < 33) (String.split_on_char '\n' accepted_text))
  in
  check "accepted tasks keep read-only composer policy"
    (Controller.contains accepted_text "Accepted task / chat history is read-only"
    && (not (Controller.contains accepted_body "must not appear"))
    && (not (Controller.contains accepted_text "draft rows"))
    && not
         (List.exists
            (fun (hit : Ui.hit) -> hit.action = Controller.Begin_compose)
            frame.hits));
  Printf.printf "Passed %d composer layout checks. Pure editor/rendering only.\n" !checks
