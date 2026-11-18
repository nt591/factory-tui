open Factory_tui
open Controller

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let hint ?(input = Normal) ?(focus = Board) ?(expanded = false) ?(searching = false)
      ?(prefix = No_prefix) width =
    Shortcut_guidance.text ~width ~input ~focus ~expanded ~searching ~prefix
  in
  check "board hints describe card navigation" (Controller.contains (hint 120) "cards");
  check "conversation hints describe scrolling not card movement"
    (Controller.contains (hint ~focus:Conversation 120) "End: latest"
    && not (Controller.contains (hint ~focus:Conversation 120) "cards"));
  check "expanded board focus uses conversation guidance"
    (hint ~expanded:true 120 = hint ~focus:Conversation ~expanded:true 120);
  check "expanded reading guidance describes return action"
    (Controller.contains (hint ~focus:Activity ~expanded:true 120) "e: return"
    && not (Controller.contains (hint ~focus:Activity ~expanded:true 120) "e: expand"));
  check "chat search hints disclose match navigation and clear action"
    (Controller.contains (hint ~focus:Conversation ~searching:true 120) "n/N: matches"
    && Controller.contains (hint ~focus:Conversation ~searching:true 120) "Esc: clear");
  check "Activity hints disclose readable and raw tools"
    (Controller.contains (hint ~focus:Activity 120) "t: tools"
    && Controller.contains (hint ~focus:Activity 120) "T: raw");
  check "pending pane prefix shows pane operations"
    (Controller.contains (hint ~prefix:Window 120) "PANE / hjkl: focus");
  List.iter
    (fun (input, marker, action, escape) ->
      let text = hint ~input 120 in
      check "input hint identifies current editor" (Controller.contains text marker);
      check "input hint states submission behavior" (Controller.contains text action);
      check "input hint states Escape behavior" (Controller.contains text escape);
      check "input hint never advertises normal-mode card navigation"
        (not (Controller.contains text "cards"));
      List.iter
        (fun width ->
          let text = hint ~input ~prefix:Window width in
          check "input guidance fits terminal width"
            (Notty.I.width (Notty.I.string Notty.A.empty text) <= max 0 width);
          check "pending normal prefix cannot replace editor guidance"
            (text = hint ~input width))
        [ -1; 0; 1; 20; 40; 60; 120 ])
    [
      (Compose, "INSERT", "Enter queues", "Esc keeps draft");
      (Edit_model, "MODEL", "Enter applies", "Esc cancels");
      (New_task, "NEW TASK", "Enter creates", "Esc cancels");
      (Search, "BOARD SEARCH", "Enter finishes", "Esc closes");
      (Chat_search, "CHAT SEARCH", "Enter finishes", "Esc clears");
    ];
  let controller = Controller.create ~external_events:true () in
  let render () =
    let frame = Ui.render controller ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 35
  in
  let saved = Controller.snapshot controller in
  check "rendered board footer uses board guidance"
    (Controller.contains (render ()) "cards");
  Controller.act controller Begin_compose;
  check "rendered composer footer shows insert controls"
    (Controller.contains (render ()) "INSERT / Enter queues");
  check "rendered hints cannot change persisted data"
    (Controller.snapshot controller = saved);
  Controller.submit controller;
  check "validation takes priority over shortcut hints"
    (Controller.contains (render ()) "Message is empty.");
  controller.input_limit <- Some 65536;
  check "input size warning takes priority over validation and hints"
    (Controller.contains (render ()) "Edit not applied / limit");
  Controller.set_input controller "Retained draft";
  Controller.key controller (`Escape, []);
  Controller.act controller (Focus Activity);
  check "rendered Activity footer shows tool controls"
    (Controller.contains (render ()) "t: tools");
  Controller.act controller (Focus Conversation);
  Chat_search.set_query controller.chat_search "needle";
  check "rendered chat search footer shows result navigation"
    (Controller.contains (render ()) "n/N: matches");
  Controller.key controller (`Escape, []);
  check "cleared chat search restores reading hints"
    (Controller.contains (render ()) "End: latest"
    && not (Controller.contains (render ()) "n/N: matches"));
  check "hints and focus changes start no process"
    (controller.live_confirmation = None
    && controller.creation_request = None
    && controller.creation_job = None);
  Printf.printf "Passed %d contextual shortcut checks. Pure input/rendering only.\n"
    !checks
