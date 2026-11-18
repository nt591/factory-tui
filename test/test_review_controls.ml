open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let make width editing files = Review_controls.make ~width ~editing ~files in
  let wide = make 120 false true in
  check "wide strip retains familiar labels and geometry"
    (wide.text = " [Refresh / r]  [jj path / i]  [Close / Esc]  [Prev file]  [Next file]"
    && List.map (fun (hit : Review_controls.hit) -> hit.x) wide.hits
       = [ 1; 16; 31; 46; 59 ]);
  let compact = make 30 false true in
  check "compact strip keeps complete primary controls"
    (compact.text = " [Refresh]  [jj]  [Close]"
    && List.map (fun (hit : Review_controls.hit) -> hit.action) compact.hits
       = [ Refresh; Edit_executable; Close ]);
  let small = make 10 false true in
  check "small strip prioritizes safe Close"
    (small.text = " [Esc]" && (List.hd small.hits).Review_controls.action = Close);
  check "too-small strip has no hidden targets"
    ((make 5 false true).text = "" && (make 5 false true).hits = []);
  let editing = make 120 true true in
  check "editing exposes only Close, not accidental refresh"
    (editing.text = " [Close / Esc]"
    && List.map (fun (hit : Review_controls.hit) -> hit.action) editing.hits = [ Close ]);
  for width = 0 to 180 do
    List.iter
      (fun (editing, files) ->
        let strip = make width editing files in
        check "control text fits terminal" (String.length strip.text <= width);
        check "each target covers an entire bracketed label"
          (List.for_all
             (fun (hit : Review_controls.hit) ->
               hit.x >= 0 && hit.width > 0
               && hit.x + hit.width <= String.length strip.text
               && strip.text.[hit.x] = '['
               && strip.text.[hit.x + hit.width - 1] = ']')
             strip.hits);
        let rec ordered = function
          | [] | [ _ ] -> true
          | a :: (b :: _ as rest) -> a.Review_controls.x + a.width <= b.x && ordered rest
        in
        check "control targets cannot overlap" (ordered strip.hits);
        check "editing cannot expose execution or file controls"
          ((not editing)
          || List.for_all
               (fun (hit : Review_controls.hit) -> hit.action = Close)
               strip.hits))
      [ (false, false); (false, true); (true, false); (true, true) ]
  done;
  let task =
    {
      (Model.make ~id:"controls" ~title:"Control fixture" ~repository:"/source") with
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
  List.iter
    (fun (width, height) ->
      let view = Review_view.render review ~width ~height in
      let buffer = Buffer.create 4096 in
      Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) view.image;
      let rows = String.split_on_char '\n' (Buffer.contents buffer) in
      check "rendered controls and targets agree"
        (List.for_all
           (fun (hit : Review_view.hit) ->
             if hit.y = 2 then true
             else
               let row = List.nth rows hit.y in
               row.[hit.x] = '[' && row.[hit.x + hit.width - 1] = ']')
           view.hits);
      check "review remains idle after responsive rendering"
        (Review.state review = Changes.Idle))
    [ (20, 8); (30, 10); (60, 20); (120, 36) ];
  Review.edit_executable review;
  let editing = Review_view.render review ~width:20 ~height:8 in
  check "path editing has usable Close mouse control"
    (List.exists (fun (hit : Review_view.hit) -> hit.action = Close) editing.hits
    && List.for_all (fun (hit : Review_view.hit) -> hit.action <> Refresh) editing.hits);
  Review.close review;
  Printf.printf "Passed %d review-control checks. Pure labels/geometry only.\n" !checks
