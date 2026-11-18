open Factory_tui

let check name condition = if not condition then failwith name

let () =
  let task = Model.make ~id:"path-task" ~title:"Edit executable" ~repository:"fixture" in
  let task =
    {
      task with
      workspace =
        Some
          {
            Model.source = "/fixture/source";
            directory = "/fixture/task";
            base = String.make 40 'a';
            name = "fixture";
          };
    }
  in
  let path = "/BEGIN/" ^ String.make 160 'x' ^ "/END" in
  let review = Result.get_ok (Review.create task ~jj:path) in
  Review.edit_executable review;
  let render width =
    let view = Review_view.render review ~width ~height:20 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, 20) view.image;
    (view, Buffer.contents buffer)
  in
  let view, text = render 60 in
  check "long path editor shows suffix and cursor" (Controller.contains text "/END▏");
  check "editing path does not expose patch scroll region" (view.scroll_region = None);
  Review.key review (`Home, []);
  let _, text = render 60 in
  check "Home shows path prefix at cursor" (Controller.contains text "▏/BEGIN/");
  Review.key review (`Arrow `Right, []);
  Review.key review (`ASCII 'Z', []);
  let _, text = render 60 in
  check "visible prefix edit changes exact path position"
    (Controller.contains text "/Z▏BEGIN/"
    && String.starts_with ~prefix:"/ZBEGIN/" (Review.executable review));
  Review.key review (`End, []);
  let _, text = render 60 in
  check "End restores editable tail" (Controller.contains text "/END▏");
  List.iter
    (fun key -> Review.key review (key, [ `Ctrl ]))
    [ `ASCII 'd'; `ASCII 'f'; `Enter ];
  check "cursor navigation never starts a command" (Review.state review = Changes.Idle);
  Review.paste_key review (`Enter, []);
  check "paste cannot submit executable"
    (Review.state review = Changes.Idle && Review.editing review);
  check "display keeps complete stored executable"
    (String.length (Review.executable review) = String.length path + 1);
  List.iter
    (fun width ->
      let view, _ = render width in
      check "editor layout remains bounded"
        (Notty.I.width view.image = width && Notty.I.height view.image = 20))
    [ 1; 5; 20; 60; 120 ];
  Review.close review;
  Printf.printf "Passed review executable cursor checks. Pure editor/rendering only.\n"
