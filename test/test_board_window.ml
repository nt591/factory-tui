open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let tasks = List.init 20 Fun.id in
  let top = Board_window.make ~capacity:3 ~selected:0 ~scroll:0 tasks in
  check "top shows first items and downward overflow"
    (top.items = [ 0; 1; 2 ]
    && top.first = 1 && top.last = 3 && top.below && not top.above);
  check "top cue shows range and direction" (Board_window.cue top = "1-3/20 ↓");
  let selected = Board_window.make ~capacity:3 ~selected:10 ~scroll:0 tasks in
  check "automatic window keeps selected item visible"
    (selected.items = [ 8; 9; 10 ] && selected.first = 9 && selected.last = 11);
  check "middle cue shows both directions" (Board_window.cue selected = "9-11/20 ↑ ↓");
  let bottom = Board_window.make ~capacity:3 ~selected:19 ~scroll:0 tasks in
  check "bottom selection fills last page"
    (bottom.items = [ 17; 18; 19 ] && bottom.above && not bottom.below);
  check "bottom cue shows no downward overflow" (Board_window.cue bottom = "18-20/20 ↑");
  let scrolled = Board_window.make ~capacity:3 ~selected:0 ~scroll:5 tasks in
  check "wheel offset can inspect away from selection" (scrolled.items = [ 5; 6; 7 ]);
  check "manual overflow clamps to final page"
    ((Board_window.make ~capacity:3 ~selected:0 ~scroll:max_int tasks).items
   = [ 17; 18; 19 ]);
  check "nonpositive scroll follows selected task"
    ((Board_window.make ~capacity:3 ~selected:10 ~scroll:(-1) tasks).items
   = selected.items);
  let all = Board_window.make ~capacity:30 ~selected:19 ~scroll:50 tasks in
  check "fitting board shows all items without cue"
    (all.items = tasks && Board_window.cue all = "");
  let hidden = Board_window.make ~capacity:0 ~selected:0 ~scroll:0 tasks in
  check "hidden board reports hidden tasks not empty data"
    (hidden.items = [] && hidden.total = 20 && hidden.first = 0 && hidden.last = 0
   && hidden.below);
  let empty = Board_window.make ~capacity:3 ~selected:0 ~scroll:10 [] in
  check "empty board has no overflow cue" (Board_window.cue empty = "" && empty.offset = 0);
  let controller = Controller.create ~external_events:true () in
  controller.tasks <-
    List.init 20 (fun i ->
        Model.make ~id:(Printf.sprintf "T-%02d" i)
          ~title:(Printf.sprintf "Task %02d" i)
          ~repository:"fixture");
  controller.selected <- "T-00";
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, text = render 120 36 in
  check "column header exposes card range"
    (Controller.contains text "Working 20 / 1-2/20");
  Controller.key controller (`Page `Down, []);
  let frame, text = render 120 36 in
  check "paging keeps selected card visible and updates range"
    (controller.selected = "T-02"
    && Controller.contains text "Working 20 / 2-3/20"
    && List.exists
         (fun (hit : Ui.hit) -> hit.action = Controller.Select "T-02")
         frame.hits);
  Controller.key controller (`ASCII 'G', []);
  let _, text = render 120 36 in
  check "last card exposes upward range" (Controller.contains text "19-20/20 ↑");
  Controller.act controller (Controller.Select "T-00");
  let _, text = render 60 20 in
  check "compact list exposes row range" (Controller.contains text "1-12/20 ↓");
  Controller.key controller (`ASCII 'G', []);
  let _, text = render 60 20 in
  check "compact final page range is exact" (Controller.contains text "9-20/20 ↑");
  controller.focus <- Controller.Board;
  let _, text = render 120 10 in
  check "too-short column does not claim no tasks"
    (Controller.contains text "Resize to show cards"
    && Controller.contains text "Working 20");
  Printf.printf "Passed %d board window checks. Pure task/layout/input data only.\n"
    !checks
