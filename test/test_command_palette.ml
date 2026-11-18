open Factory_tui
open Controller

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ctrl_p t = Controller.key t (`ASCII 'P', [ `Ctrl ])
let type_text t text = String.iter (fun char -> Controller.key t (`ASCII char, [])) text
let task = Model.make ~id:"palette" ~title:"Talk to an agent" ~repository:"fixture"

let create () =
  let t = Controller.create ~external_events:true () in
  t.tasks <- [ { task with state = Model.Ready } ];
  t.selected <- task.id;
  t.drafts <- [ (task.id, "Saved reply") ];
  t

let () =
  List.iter
    (fun input ->
      let t = create () in
      t.input <- input;
      t.editor <- Text_edit.left (Text_edit.create "Retained input");
      t.input_error <- Some "Fixture error";
      t.input_limit <- Some 256;
      let editor = t.editor and saved = Controller.snapshot t and focus = t.focus in
      ctrl_p t;
      check "Ctrl-P opens from all nonmodal editor modes" (t.commands <> None);
      type_text t "archive";
      let entries = Command_palette.visible (Option.get t.commands) in
      check "search separates destination and task lifecycle"
        (List.exists
           (fun (entry : Command_palette.entry) -> entry.title = "Open Archive")
           entries
        && List.exists
             (fun (entry : Command_palette.entry) ->
               entry.title = "Accept & archive task")
             entries);
      Controller.key t (`Escape, []);
      check "cancel restores exact editor cursor mode focus and errors"
        (t.commands = None && t.input = input && t.editor == editor && t.focus = focus
        && t.input_error = Some "Fixture error"
        && t.input_limit = Some 256
        && Controller.snapshot t = saved);
      ctrl_p t;
      ctrl_p t;
      check "Ctrl-P also closes without consuming the draft"
        (t.commands = None && t.editor == editor))
    [ Normal; Compose; Search; Chat_search; New_task; Edit_model ];
  let t = create () in
  Controller.act t Begin_compose;
  let saved = Controller.snapshot t in
  ctrl_p t;
  String.iter (fun char -> Controller.paste_key t (`ASCII char, [])) "Open Archive";
  Controller.paste_key t (`Enter, []);
  check "bracketed paste cannot execute commands"
    (t.commands <> None && (not t.archive) && Controller.snapshot t = saved);
  List.iter
    (fun (width, height) ->
      let frame = Ui.render t ~width ~height in
      check "palette suppresses background controls"
        (frame.panes = [] && frame.columns = [] && frame.scroll_panes = []
        && List.for_all
             (fun (hit : Ui.hit) ->
               match hit.action with
               | Choose_command _ | Close_commands -> true
               | _ -> false)
             frame.hits);
      check "palette frame fits"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 20); (120, 36); (240, 50) ];
  let frame = Ui.render t ~width:120 ~height:36 in
  Ui.mouse t frame ~now:0. (`Press `Left, (1, 1), []);
  check "background tab click cannot leave a command modal"
    (t.commands <> None && not t.archive);
  Controller.key t (`Enter, []);
  check "Archive command exits insert with board focus"
    (t.commands = None && t.archive && (not t.zoom) && t.focus = Board && t.input = Normal);
  check "navigation command preserves all task data and drafts"
    (Controller.snapshot t = saved);
  ctrl_p t;
  type_text t "accept";
  t.tasks <- [ { task with state = Model.Working } ];
  Controller.key t (`Enter, []);
  check "command availability is rechecked after a task update"
    (t.commands <> None && (Option.get (Controller.selected t)).state = Model.Working);
  let entries = Command_palette.visible (Option.get t.commands) in
  check "unavailable command gives a reason"
    (List.for_all (fun (entry : Command_palette.entry) -> entry.disabled <> None) entries);
  Controller.key t (`Escape, []);
  t.tasks <- [ { task with state = Model.Ready } ];
  ctrl_p t;
  type_text t "accept";
  Controller.key t (`Enter, []);
  check "accept command archives only the selected task"
    ((Option.get (Controller.selected t)).state = Model.Done && t.commands = None);
  ctrl_p t;
  type_text t "restore";
  Controller.key t (`Enter, []);
  check "restore command reveals Ready card"
    ((Option.get (Controller.selected t)).state = Model.Ready
    && (not t.archive) && t.focus = Board);
  Controller.act t Begin_compose;
  ctrl_p t;
  type_text t "delete";
  Controller.key t (`Enter, []);
  check "Delete is unavailable inside a task view"
    (t.commands <> None && t.deletion = None);
  Controller.key t (`Escape, []);
  check "palette cancel preserves original insert mode"
    (t.input = Compose && Controller.draft t = "Saved reply");
  Controller.key t (`Escape, []);
  ctrl_p t;
  type_text t "delete";
  Controller.key t (`Enter, []);
  check "board Delete command opens confirmation" (t.commands = None && t.deletion <> None);
  Controller.key t (`ASCII 'n', []);
  ctrl_p t;
  type_text t "reply";
  Controller.key t (`Enter, []);
  check "Reply command resumes insert without sending"
    (t.input = Compose && t.focus = Conversation && Controller.draft t = "Saved reply");
  ctrl_p t;
  type_text t "no such action";
  Controller.key t (`Enter, []);
  check "no matches cannot execute an action"
    (t.commands <> None && Command_palette.visible (Option.get t.commands) = []);
  Controller.key t (`Escape, []);
  check "palette operations start no agent or creation"
    ((Option.get (Controller.selected t)).active = None
    && t.creation_request = None && t.creation_job = None);
  let empty =
    Command_palette.catalogue ~board:true ~task:None ~live:false ~replay:true
      ~storage:false ~busy:false
  in
  check "task commands are disabled without a task"
    (List.for_all
       (fun (entry : Command_palette.entry) ->
         match entry.command with
         | Reply | Model | Stop | Accept | Restore | Delete | Review ->
             entry.disabled <> None
         | _ -> true)
       empty);
  let palette = Command_palette.create empty in
  for _ = 0 to 400 do
    Command_palette.insert palette "x"
  done;
  check "command search is bounded" (String.length (Command_palette.query palette) = 256);
  Printf.printf
    "Passed %d command palette checks. Pure input/rendering; no network, agent or storage.\n"
    !checks
