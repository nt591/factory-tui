open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let idle = Review_notice.rows ~width:120 Changes.Idle in
  check "wide idle notice remains one row"
    (List.length idle = 1 && Controller.contains (List.hd idle) "No agent starts");
  let long = "Diagnostic " ^ String.make 200 'x' ^ "ERROR_END\nRetained explanation" in
  let rows = Review_notice.rows ~width:30 (Changes.Error long) in
  check "error details wrap completely"
    (Controller.contains (String.concat "" rows) "ERROR_END");
  check "retry guidance remains after error"
    (String.ends_with ~suffix:"explicitly." (List.hd (List.rev rows)));
  check "explicit diagnostic line boundary retained"
    (List.exists (( = ) "Retained explanation") rows);
  let invalid =
    Review_notice.rows ~width:120 (Changes.Error "Bad\255\027\194\128\nNext")
  in
  check "notice sanitizes malformed bytes and controls"
    (List.hd invalid = "Changes error: Bad�  " && List.nth invalid 1 = "Next");
  check "real patch contents do not become wrapped notices"
    (Review_notice.rows ~width:30 (Changes.Patch "diff --git a/a b/a\n+long") = []);
  check "empty patch keeps review result notice"
    (Controller.contains
       (String.concat " " (Review_notice.rows ~width:30 (Changes.Patch "")))
       "recorded base");
  List.iter
    (fun width ->
      List.iter
        (fun state ->
          let rows = Review_notice.rows ~width state in
          check "notice rows fit available cells"
            (List.for_all
               (fun row ->
                 Notty.I.width (Notty.I.string Notty.A.empty row) <= max 1 width)
               rows))
        [ Changes.Idle; Changes.Loading; Changes.Error long; Changes.Patch "" ])
    [ 1; 2; 20; 30; 60; 120 ];
  let task = Model.make ~id:"notice" ~title:"Review fixture" ~repository:"/source" in
  let task =
    {
      task with
      workspace =
        Some
          {
            Model.source = "/source";
            directory = "/task";
            base = String.make 40 'a';
            name = "fixture";
          };
    }
  in
  let review = Result.get_ok (Review.create task ~jj:"/never/run") in
  let render width height = Review_view.render review ~width ~height in
  let view = render 20 8 in
  check "notice paging uses actual body rows" ((Option.get view.scroll_region).height = 2);
  Review.key review (`End, []);
  let view = render 20 8 in
  let text = Buffer.create 4096 in
  Notty.Render.to_buffer text Notty.Cap.dumb (0, 0) (20, 8) view.image;
  check "End reaches final wrapped idle guidance"
    (Controller.contains (Buffer.contents text) "starts."
    && Review.scroll review = List.length (Review_notice.rows ~width:20 Changes.Idle) - 2
    );
  check "notice paging starts no process" (Review.state review = Changes.Idle);
  Review.key review (`Home, []);
  ignore (render 20 8);
  check "Home resets notice window" (Review.scroll review = 0);
  Review.key review (`ASCII 'f', [ `Ctrl ]);
  check "notice full paging uses rendered capacity" (Review.scroll review = 2);
  List.iter
    (fun (width, height) ->
      let view = render width height in
      check "notice frame dimensions are exact"
        (Notty.I.width view.image = width && Notty.I.height view.image = height))
    [ (1, 1); (20, 8); (60, 20); (120, 36) ];
  Review.close review;
  Printf.printf "Passed %d review notice checks. Supplied notices/layout only.\n" !checks
