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
  Printf.printf "Passed %d board navigation checks. Pure task/input/layout state only.\n"
    !checks
