open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let t = Controller.create ~external_events:true () in
  let task = Model.make ~id:"task" ~title:"Read activity output" ~repository:"fixture" in
  let command =
    "inspect all of this command without a narrow sidebar wrapping every few words"
  in
  let payload =
    Yojson.Basic.to_string
      (`Assoc
         [
           ("type", `String "command_execution");
           ("id", `String "command");
           ("command", `String command);
           ("status", `String "completed");
           ("exit_code", `Int 0);
           ( "aggregated_output",
             `String
               (String.concat "\n"
                  (List.init 50 (fun i -> Printf.sprintf "Output line %02d" i))) );
         ])
  in
  t.tasks <- [ { task with tools = [ ("run/command", payload) ] } ];
  t.selected <- task.id;
  Controller.act t Controller.Begin_compose;
  Controller.set_input t "Keep my draft";
  Controller.key t (`Escape, []);
  Controller.act t (Controller.Focus Controller.Activity);
  Controller.act t Controller.Toggle_tools;
  let snapshot = Controller.snapshot t in
  let render width height =
    let frame = Ui.render t ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, normal = render 120 36 in
  check "unexpanded details wrap long command" (not (Controller.contains normal command));
  let original_scroll = t.scroll in
  Controller.key t (`ASCII 'e', []);
  check "Activity e expands without changing focus"
    (t.zoom && t.activity_expanded && t.focus = Controller.Activity);
  check "expanding Activity retains vertical offset" (t.scroll = original_scroll);
  let frame, expanded = render 120 36 in
  check "expanded Activity shows long command on one line"
    (Controller.contains expanded command);
  check "expanded Activity shows hidden output range without reducing capacity"
    (Controller.contains (List.nth (String.split_on_char '\n' expanded) 32) "rows 1-28/"
    && t.page_rows = 28);
  check "expanded pane identifies task"
    (Controller.contains expanded "task / activity / expanded");
  check "expanded Activity hides chat and composer"
    ((not (Controller.contains expanded "Reply / next turn"))
    && not (Controller.contains expanded "conversation"));
  check "expanded Activity hitbox uses full terminal width"
    (List.exists
       (fun (hit : Ui.hit) ->
         hit.action = Controller.Focus Controller.Activity && hit.rect.w = 120)
       frame.hits);
  Controller.key t (`ASCII 'j', []);
  check "j scrolls expanded tool output" (t.scroll = 1);
  Controller.key t (`ASCII 'G', []);
  let _, bottom = render 120 36 in
  check "G reaches end of expanded tool output"
    (Controller.contains bottom "Output line 49");
  let total =
    Activity_content.lines ~now:0. ~expanded:true ~raw:false ~waiting:false
      (Controller.selected t)
    |> List.concat_map (Ui.wrap 116)
    |> List.length
  in
  let footer = List.nth (String.split_on_char '\n' bottom) 32 in
  check "Activity bottom range matches output and indicates only content above"
    (Controller.contains footer
       (Printf.sprintf "rows %d-%d/%d ↑" (total - 27) total total)
    && not (Controller.contains footer "↓"));
  Controller.key t (`ASCII 'g', []);
  Controller.key t (`ASCII 'g', []);
  ignore (render 120 36);
  check "gg returns to start of expanded Activity" (t.scroll = 0);
  Controller.key t (`ASCII 'T', []);
  let _, raw = render 120 36 in
  check "raw tool diagnostics remain available in expanded pane"
    (t.raw_tools && Controller.contains raw "command_execution");
  Controller.key t (`ASCII 'T', []);
  List.iter
    (fun (width, height) ->
      let frame, _ = render width height in
      check "expanded Activity frame bounds"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
      List.iter
        (fun (hit : Ui.hit) ->
          let r = hit.rect in
          check "expanded Activity hit bounds"
            (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height))
        frame.hits)
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  Controller.key t (`Escape, []);
  check "Activity Escape restores split layout and focus"
    ((not t.zoom) && (not t.activity_expanded) && t.focus = Controller.Activity);
  Controller.key t (`ASCII 'e', []);
  Controller.key t (`ASCII 'e', []);
  check "Activity e stays expanded" (t.zoom && t.focus = Controller.Activity);
  Controller.key t (`Escape, []);
  Controller.act t (Controller.Focus Controller.Board);
  Controller.key t (`Enter, []);
  check "board Enter still expands chat"
    (t.zoom && (not t.activity_expanded) && t.focus = Controller.Conversation);
  check "opening writable task defaults to insert" (t.input = Controller.Compose);
  Controller.key t (`Escape, []);
  Controller.act t (Controller.Focus Controller.Activity);
  Controller.key t (`ASCII 'e', []);
  check "Activity can expand from expanded task layout"
    (t.activity_expanded && t.activity_origin_zoom);
  Controller.key t (`Escape, []);
  check "nested Activity Escape restores expanded task layout"
    (t.zoom && (not t.activity_expanded) && t.focus = Controller.Activity);
  Controller.key t (`ASCII 'e', []);
  Controller.key t (`Tab, []);
  check "Tab exits Activity-only layout into visible chat"
    (t.zoom && (not t.activity_expanded) && t.focus = Controller.Conversation);
  Controller.act t (Controller.Focus Controller.Activity);
  Controller.key t (`ASCII 'e', []);
  Controller.key t (`ASCII 'i', []);
  check "compose leaves Activity-only layout"
    ((not t.activity_expanded) && t.input = Controller.Compose
    && t.focus = Controller.Conversation);
  check "compose keeps task draft" (Controller.draft t = "Keep my draft");
  Controller.key t (`Escape, []);
  Controller.act t (Controller.Focus Controller.Activity);
  Controller.key t (`ASCII 'e', []);
  Controller.key t (`ASCII 'S', []);
  check "chat search opens visible conversation from expanded Activity"
    ((not t.activity_expanded)
    && t.focus = Controller.Conversation
    && t.input = Controller.Chat_search);
  Controller.key t (`Escape, []);
  Controller.act t (Controller.Focus Controller.Activity);
  Controller.key t (`ASCII 'e', []);
  Controller.key t (`ASCII 'b', []);
  check "return to board closes Activity-only layout"
    ((not t.zoom) && (not t.activity_expanded) && t.focus = Controller.Board);
  check "expansion never changes saved conversations or drafts"
    (Controller.snapshot t = snapshot);
  check "expansion starts no run" ((Option.get (Controller.selected t)).active = None);
  let short = Controller.create ~external_events:true () in
  short.tasks <- [ Model.make ~id:"short" ~title:"Short activity" ~repository:"fixture" ];
  short.selected <- "short";
  short.focus <- Controller.Activity;
  short.zoom <- true;
  short.activity_expanded <- true;
  let frame = Ui.render short ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "fitting Activity has no false overflow cue"
    (not
       (Controller.contains
          (List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 32)
          "rows "));
  Printf.printf "Passed %d pane expansion checks. Rendering and navigation only.\n"
    !checks
