open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let message id author text : message = { id; author; text; queued = false }

let () =
  let search = Chat_search.create () in
  let messages =
    [
      message "first" "You" "NEEDLE at first";
      message "middle" "Codex" "unmatched";
      message "last" "Codex" "last needle needle 界";
    ]
  in
  Chat_search.set_query search "needle";
  Chat_search.sync search messages;
  check "case insensitive ASCII matches count once per message"
    (Chat_search.position search = (1, 2));
  check "seek anchors to first message" (Chat_search.seek search = Some "first");
  check "seek consumed exactly once" (Chat_search.seek search = None);
  Chat_search.sync search messages;
  check "unchanged sync does not recreate a seek" (Chat_search.seek search = None);
  check "cached membership retains all matching identities"
    (Chat_search.matches search "first"
    && Chat_search.matches search "last"
    && not (Chat_search.matches search "middle"));

  Chat_search.move search ~backwards:false;
  check "next message selected"
    (Chat_search.current search = Some "last" && Chat_search.position search = (2, 2));
  Chat_search.move search ~backwards:false;
  check "next wraps" (Chat_search.current search = Some "first");
  Chat_search.move search ~backwards:true;
  check "previous wraps" (Chat_search.current search = Some "last");
  Chat_search.sync search (messages @ [ message "new" "You" "new needle" ]);
  check "new updates retain selected message ID"
    (Chat_search.current search = Some "last" && Chat_search.position search = (2, 3));
  check "new immutable list refreshes membership" (Chat_search.matches search "new");

  Chat_search.sync search
    [ message "first" "You" "needle"; message "last" "Codex" "streamed item changed" ];
  check "replacement removing match selects surviving message"
    (Chat_search.current search = Some "first");
  check "removed match leaves no stale highlighting"
    ((not (Chat_search.matches search "last")) && not (Chat_search.matches search "new"));

  Chat_search.set_query search "界";
  Chat_search.sync search messages;
  check "Unicode literal matches" (Chat_search.current search = Some "last");
  Chat_search.set_query search "Codex";
  Chat_search.sync search messages;
  check "author searchable" (Chat_search.position search = (1, 2));
  Chat_search.set_query search ".*";
  Chat_search.sync search messages;
  check "query is literal not regex" (Chat_search.position search = (0, 0));
  Chat_search.move search ~backwards:false;
  check "no-match navigation safe" (Chat_search.current search = None);
  Chat_search.set_query search (String.make 257 'x');
  check "query length bounded" (Chat_search.query search = ".*");
  Chat_search.clear search;
  check "clear resets transient state"
    (Chat_search.query search = "" && Chat_search.position search = (0, 0));
  check "clear removes cached highlight membership"
    (not (Chat_search.matches search "last"));
  Chat_search.set_query search "needle";
  Chat_search.sync search messages;
  check "query change invalidates cache for same message list"
    (Chat_search.position search = (1, 2));
  Chat_search.set_query search "unmatched";
  Chat_search.sync search messages;
  check "same list is searched again for replacement query"
    (Chat_search.current search = Some "middle"
    && not (Chat_search.matches search "first"));
  Chat_search.clear search;
  Chat_search.sync search messages;
  check "empty query never highlights content" (Chat_search.position search = (0, 0));

  let controller = Controller.create ~external_events:true () in
  let task = make ~id:"chat" ~title:"Task chat" ~repository:"fixture" in
  let fillers =
    List.init 25 (fun n ->
        message (string_of_int n) "Agent" ("Filler " ^ string_of_int n))
  in
  controller.tasks <-
    [
      {
        task with
        messages =
          (message "first" "You" "First needle" :: fillers)
          @ [ message "last" "Agent" "Last needle" ];
      };
    ];
  controller.selected <- "chat";
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "Preserve draft";
  Controller.key controller (`Escape, []);
  let before = Controller.snapshot controller in
  Controller.key controller (`ASCII '/', []);
  check "focused chat slash opens transcript search"
    (controller.input = Controller.Chat_search);
  Controller.set_input controller "needle";
  Controller.key controller (`Enter, []);
  let render width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, Buffer.contents buffer)
  in
  let _, text = render 120 36 in
  check "match count displayed" (Controller.contains text "1/2 messages");
  check "search scrolls to old match" (Controller.contains text "First needle");
  check "search leaves board query untouched" (controller.query = "");
  check "search preserves persisted task draft and content"
    (Controller.snapshot controller = before);
  Controller.key controller (`ASCII 'n', []);
  let _, text = render 120 36 in
  check "n selects second matching message"
    (Chat_search.position controller.chat_search = (2, 2)
    && Controller.contains text "Last needle");
  check "n does not create new task while searching chat"
    (List.length controller.tasks = 1);
  Controller.key controller (`ASCII 'N', []);
  ignore (render 120 36);
  check "N selects previous match" (Chat_search.position controller.chat_search = (1, 2));
  List.iter
    (fun (width, height) ->
      let frame, _ = render width height in
      check "search frame bounds"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 20); (80, 24); (120, 36); (180, 50) ];
  Controller.key controller (`Escape, []);
  check "Escape clears search before leaving task"
    (Chat_search.query controller.chat_search = "" && controller.selected = "chat");
  Controller.act controller (Controller.Focus Controller.Board);
  Controller.key controller (`ASCII '/', []);
  check "board slash keeps board filtering" (controller.input = Controller.Search);
  Controller.key controller (`Escape, []);
  Controller.key controller (`ASCII 'S', []);
  check "S opens chat search from board"
    (controller.input = Controller.Chat_search
    && controller.focus = Controller.Conversation);
  Controller.paste_key controller (`ASCII 's', []);
  Controller.paste_key controller (`Enter, []);
  check "paste is search text not run or submit"
    (Chat_search.query controller.chat_search = "s "
    && controller.input = Controller.Chat_search
    && (Option.get (Controller.selected controller)).active = None);
  Controller.set_input controller (String.make 257 'x');
  check "rejected long query preserves editor and query"
    (Chat_search.query controller.chat_search = "s "
    && Text_edit.text controller.editor = "s ");
  Controller.key controller (`Escape, []);
  check "editing Escape cancels search"
    (controller.input = Controller.Normal && Chat_search.query controller.chat_search = "");
  Controller.act controller Controller.Begin_chat_search;
  Controller.set_input controller "absent";
  Controller.submit controller;
  let _, text = render 120 36 in
  check "no matches explicitly counted" (Controller.contains text "0/0 messages");
  Controller.act controller (Controller.Select "missing");
  check "switching task clears chat search" (Chat_search.query controller.chat_search = "");
  Printf.printf "Passed %d chat search checks. No process or storage access.\n" !checks
