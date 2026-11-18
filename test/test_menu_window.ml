open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let rows = List.init 40 (Printf.sprintf "row %02d")

let () =
  let top = Menu_window.make ~height:20 ~scroll:0 rows in
  check "window reserves UI rows" (top.capacity = 15 && List.length top.rows = 15);
  check "top reports visible range and overflow"
    (top.first = 1 && top.last = 15 && top.total = 40 && (not top.above) && top.below);
  check "top cue exposes more below"
    (Controller.contains (Menu_window.position top) "more below");
  let middle = Menu_window.make ~height:20 ~scroll:15 rows in
  check "page range starts at requested offset"
    (middle.rows = List.filteri (fun i _ -> i >= 15 && i < 30) rows);
  check "middle reports both overflow directions" (middle.above && middle.below);
  let bottom = Menu_window.make ~height:20 ~scroll:max_int rows in
  check "bottom clamps to last full window"
    (bottom.scroll = 25 && bottom.first = 26 && bottom.last = 40 && not bottom.below);
  check "negative scroll clamps to top"
    ((Menu_window.make ~height:20 ~scroll:(-5) rows).scroll = 0);
  let empty = Menu_window.make ~height:20 ~scroll:10 [] in
  check "empty menu range is zero" (empty.first = 0 && empty.last = 0 && empty.scroll = 0);
  let tiny = Menu_window.make ~height:1 ~scroll:0 rows in
  check "tiny menu exposes no covered content"
    (tiny.capacity = 0 && tiny.rows = [] && tiny.below);
  let controller = Controller.create ~external_events:true () in
  Controller.act controller Controller.Help;
  let saved = Controller.snapshot controller in
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, text = render 80 20 in
  check "short help shows overflow cue" (Controller.contains text "more below");
  let capacity = controller.menu_page_rows in
  Controller.key controller (`Page `Down, []);
  check "page key uses current menu capacity" (controller.menu_scroll = capacity);
  let _, text = render 80 20 in
  check "scrolled menu retains position cue" (Controller.contains text "more");
  Controller.key controller (`End, []);
  let _, text = render 80 20 in
  check "bottom reaches final help instructions"
    (Controller.contains text "Menu: Tab/h/l switches tabs");
  check "bottom cue exposes content above" (Controller.contains text "more above");
  Controller.key controller (`Tab, []);
  check "tab switch resets menu position" (controller.menu_scroll = 0);
  ignore (render 80 20);
  Controller.key controller (`Page `Down, []);
  check "settings paging uses its visible capacity"
    (controller.menu_scroll = controller.menu_page_rows);
  List.iter
    (fun (width, height) ->
      let frame, _ = render width height in
      check "menu frame remains bounded"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      check "menu blocks background controls"
        (List.for_all
           (fun (hit : Ui.hit) ->
             match hit.action with Controller.Menu_tab _ -> true | _ -> false)
           frame.hits))
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  check "menu navigation does not change saved tasks or drafts"
    (Controller.snapshot controller = saved);
  Controller.key controller (`Escape, []);
  check "Escape closes menu" (not controller.help);
  Printf.printf "Passed %d menu window checks. Pure content and input only.\n" !checks
