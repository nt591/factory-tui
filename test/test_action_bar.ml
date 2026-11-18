open Factory_tui
open Model
open Controller

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let has items action = List.exists (fun (_, actual) -> actual = action) items

let items ?(live = false) ?(replay = false) ?(fake = false) ?(storage = false)
    ?(expanded = false) task =
  Action_bar.items ~task ~live ~replay ~fake ~storage ~expanded

let task = Model.make ~id:"task" ~title:"Instruction" ~repository:"fixture"

let () =
  let empty = items None in
  check "empty bar has navigation and demo creation"
    (has empty Help && has empty Begin_new && has empty Quit);
  check "empty bar omits task actions"
    (List.for_all
       (fun action -> not (has empty action))
       [ Start; Stop; Accept; Zoom; Begin_compose; Open_review ]);
  check "workspace creation requires storage" (not (has empty Begin_workspace));
  check "configured storage offers workspace creation"
    (has (items ~storage:true None) Begin_workspace);
  let queued = items (Some task) in
  check "queued task offers reply and start" (has queued Begin_compose && has queued Start);
  check "queued task omits stop and accept"
    ((not (has queued Stop)) && not (has queued Accept));
  let working = items (Some { task with state = Working }) in
  check "working task offers stop and queued reply"
    (has working Stop && has working Begin_compose);
  check "working task cannot offer another start" (not (has working Start));
  let ready = items (Some { task with state = Ready; messages = [] }) in
  check "ready task offers acceptance but not empty restart"
    (has ready Accept && not (has ready Start));
  let done_items = items (Some { task with state = Done }) in
  check "accepted task offers inspection only"
    (has done_items Zoom
    && List.for_all
         (fun action -> not (has done_items action))
         [ Start; Stop; Accept; Begin_compose; Begin_model; Next_harness ]);
  check "replay suppresses process controls and pause"
    (List.for_all
       (fun action -> not (has (items ~replay:true (Some task)) action))
       [ Start; Stop; Toggle_pause ]);
  check "fake mode suppresses timer pause"
    (not (has (items ~fake:true (Some task)) Toggle_pause));
  check "live task without workspace cannot offer start"
    (not (has (items ~live:true (Some task)) Start));
  let workspace =
    {
      source = "/fixture/source";
      directory = "/fixture/task";
      base = String.make 40 'a';
      name = "fixture";
    }
  in
  let live_task = { task with workspace = Some workspace } in
  let live_items = items ~live:true ~storage:true (Some live_task) in
  check "live workspace offers confirmation and review"
    (has live_items Start && has live_items Open_review
    && List.mem ("s confirm", Start) live_items);
  check "live bar omits unsupported harness cycling and pause"
    ((not (has live_items Next_harness)) && not (has live_items Toggle_pause));
  check "Claude live task cannot offer execution"
    (not (has (items ~live:true (Some { live_task with harness = Claude })) Start));
  check "return label reflects expansion"
    (List.mem ("e return", Zoom) (items ~expanded:true (Some task)));
  let controller = Controller.create ~external_events:true () in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  let frame = Ui.render controller ~width:120 ~height:36 in
  let bottom_actions = List.filter (fun (hit : Ui.hit) -> hit.rect.y = 34) frame.hits in
  check "rendered replay footer excludes start stop and acceptance hitboxes"
    (List.for_all
       (fun (hit : Ui.hit) -> not (List.mem hit.action [ Start; Stop; Accept ]))
       bottom_actions);
  Controller.key controller (`ASCII 's', []);
  check "hidden shortcut still passes normal replay validation"
    ((Option.get (Controller.selected controller)).active = None
    && Controller.contains controller.status "Replay mode");
  controller.tasks <- [ { live_task with state = Ready; messages = [] } ];
  let frame = Ui.render controller ~width:60 ~height:20 in
  check "compact ready footer prioritizes acceptance and real review"
    (List.exists (fun (hit : Ui.hit) -> hit.rect.y = 18 && hit.action = Accept) frame.hits
    && List.exists
         (fun (hit : Ui.hit) -> hit.rect.y = 18 && hit.action = Open_review)
         frame.hits);
  Printf.printf "Passed %d contextual action checks. Pure state and rendering only.\n"
    !checks
