open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let make id state =
  { (Model.make ~id ~title:("Task " ^ id) ~repository:"fixture") with state }

let () =
  let controller = Controller.create ~external_events:true () in
  let tasks =
    [
      make "one" Queued;
      make "two" Ready;
      make "three" Needs_you;
      make "four" Queued;
      make "five" Ready;
    ]
  in
  controller.tasks <- tasks;
  controller.selected <- "one";
  let render width height = ignore (Ui.render controller ~width ~height) in
  render 60 20;
  check "compact renderer selects list navigation" controller.board_list;
  Controller.key controller (`ASCII 'j', []);
  check "compact j selects next displayed task across states" (controller.selected = "two");
  Controller.key controller (`Arrow `Down, []);
  check "compact down arrow selects next displayed task" (controller.selected = "three");
  Controller.key controller (`ASCII 'k', []);
  check "compact k selects previous displayed task" (controller.selected = "two");
  Controller.key controller (`ASCII 'g', []);
  Controller.key controller (`ASCII 'g', []);
  check "compact gg reaches first list task" (controller.selected = "one");
  Controller.key controller (`ASCII 'G', []);
  check "compact G reaches final list task" (controller.selected = "five");
  Controller.key controller (`ASCII 'k', []);
  check "compact up crosses a state boundary" (controller.selected = "four");
  Controller.key controller (`ASCII '2', []);
  Controller.key controller (`ASCII 'k', []);
  check "compact counted motion follows display order" (controller.selected = "two");
  Controller.key controller (`ASCII 'l', []);
  check "compact horizontal motion follows list order" (controller.selected = "three");
  Controller.key controller (`ASCII 'h', []);
  check "compact reverse horizontal motion follows list order"
    (controller.selected = "two");
  controller.query <- "four";
  render 60 20;
  Controller.key controller (`ASCII 'G', []);
  check "compact navigation respects filters" (controller.selected = "four");
  controller.query <- "";
  Controller.act controller (Controller.Select "one");
  render 120 36;
  check "four-column renderer restores column navigation" (not controller.board_list);
  Controller.key controller (`ASCII 'j', []);
  check "column j stays within selected state" (controller.selected = "four");
  Controller.key controller (`ASCII 'l', []);
  check "column l moves into next nonempty state" (controller.selected = "three");
  render 60 20;
  Controller.key controller (`ASCII 'j', []);
  check "resize immediately switches to displayed list order"
    (controller.selected = "four");
  controller.tasks <-
    List.map
      (fun (task : task) ->
        if task.id = "four" then { task with state = Working } else task)
      controller.tasks;
  render 60 20;
  Controller.key controller (`ASCII 'j', []);
  check "automatic state change does not reorder compact list navigation"
    (controller.selected = "five");
  Controller.act controller (Controller.Select "one");
  render 60 10;
  let capacity = controller.page_rows in
  Controller.key controller (`Page `Down, []);
  check "compact paging moves by visible list capacity"
    (controller.selected = (List.nth tasks capacity).id);
  let saved = Controller.snapshot controller in
  render 120 36;
  render 60 20;
  check "layout mode is not persisted" (Controller.snapshot controller = saved);
  let dense =
    [
      make "q0" Queued;
      make "q1" Queued;
      make "q2" Queued;
      make "w0" Working;
      make "w1" Working;
      make "w2" Working;
      make "r0" Ready;
      make "r1" Ready;
    ]
  in
  check "right preserves source ordinal"
    (Board_navigation.horizontal ~right:true ~selected:"q2" dense = Some "w2");
  check "left preserves source ordinal"
    (Board_navigation.horizontal ~right:false ~selected:"w1" dense = Some "q1");
  check "shorter column clamps row and skips empty state"
    (Board_navigation.horizontal ~right:true ~selected:"w2" dense = Some "r1");
  check "outer column does not wrap"
    (Board_navigation.horizontal ~right:true ~selected:"r1" dense = None);
  check "missing filtered selection does not invent horizontal move"
    (Board_navigation.horizontal ~right:true ~selected:"missing" dense = None);
  check "no columns are safe"
    (Board_navigation.horizontal ~right:false ~selected:"q0" [] = None);
  let single = [ make "q" Queued ] in
  check "single column has no horizontal destination"
    (Board_navigation.horizontal ~right:true ~selected:"q" single = None);
  check "vertical column selection follows filtered order"
    (List.map
       (fun (task : Model.task) -> task.id)
       (Board_navigation.vertical ~columns:true ~selected:"q1" dense)
    = [ "q0"; "q1"; "q2" ]);
  check "compact vertical navigation preserves all displayed tasks"
    (Board_navigation.vertical ~columns:false ~selected:"q1" dense = dense);
  check "missing selection vertical fallback uses column order"
    (List.map
       (fun (task : Model.task) -> task.id)
       (Board_navigation.vertical ~columns:true ~selected:"missing"
          [ make "r" Ready; make "q" Queued ])
    = [ "q"; "r" ]);
  check "extreme motion clamps without overflow"
    (Board_navigation.move ~selected:"q1" ~delta:max_int dense = Some "r1"
    && Board_navigation.move ~selected:"q1" ~delta:min_int dense = Some "q0");
  check "missing selection enters list from correct edge"
    (Board_navigation.move ~selected:"missing" ~delta:1 dense = Some "q0"
    && Board_navigation.move ~selected:"missing" ~delta:(-1) dense = Some "r1");
  check "empty list movement and edges are safe"
    (Board_navigation.move ~selected:"missing" ~delta:1 [] = None
    && Board_navigation.edge ~last:true [] = None);
  controller.tasks <- dense;
  Controller.act controller (Controller.Select "q2");
  render 120 36;
  let saved = Controller.snapshot controller in
  Controller.key controller (`ASCII 'l', []);
  check "controller horizontal move selects aligned card" (controller.selected = "w2");
  render 120 36;
  Controller.key controller (`ASCII 'l', []);
  check "controller skips empty column and clamps destination" (controller.selected = "r1");
  let frame = Ui.render controller ~width:120 ~height:36 in
  check "aligned destination is a visible click target"
    (List.exists (fun (hit : Ui.hit) -> hit.action = Controller.Select "r1") frame.hits);
  check "navigation changes only selected identity"
    ((Controller.snapshot controller).tasks = saved.tasks
    && (Controller.snapshot controller).drafts = saved.drafts);
  controller.query <- "0";
  render 120 36;
  Controller.act controller (Controller.Select "q0");
  Controller.key controller (`ASCII 'l', []);
  check "horizontal selection uses visible filtered row" (controller.selected = "w0");
  controller.query <- "";
  Controller.act controller (Controller.Select "q2");
  controller.tasks <-
    List.map
      (fun (task : Model.task) ->
        if task.id = "q2" then { task with state = Working } else task)
      controller.tasks;
  render 120 36;
  Controller.key controller (`ASCII 'l', []);
  check "state movement uses current destination ordinal" (controller.selected = "r0");
  Printf.printf "Passed %d board navigation checks. Pure task/input/layout state only.\n"
    !checks
