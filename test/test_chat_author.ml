open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let header document =
  List.filter
    (fun (row : Chat_layout.row) -> match row.tone with Author _ -> true | _ -> false)
    (Chat_layout.rows document)

let () =
  let author = "Fixture agent " ^ String.make 190 'a' ^ "AUTHOR_END" in
  let message : Model.message =
    { id = "long-author"; author; text = "Body start\nBody next"; queued = true }
  in
  let cache = Chat_layout.create () in
  let document = Chat_layout.update cache ~task_id:"task" ~width:32 [ message ] in
  let headings = header document in
  check "long author and delivery suffix wrap completely"
    (Controller.contains
       (String.concat "" (List.map (fun row -> row.Chat_layout.text) headings))
       "AUTHOR_END"
    && String.ends_with ~suffix:"/ queued"
         (String.concat "" (List.map (fun row -> row.Chat_layout.text) headings)));
  check "every header row retains queued tone"
    (List.for_all (fun row -> row.Chat_layout.tone = Author true) headings);
  check "body row indices do not depend on author length"
    (List.exists
       (fun row -> row.Chat_layout.index = 1 && row.text = "Body start")
       (Chat_layout.rows document));
  check "header anchor indices increase through zero"
    (List.map (fun row -> row.Chat_layout.index) headings
    = List.init (List.length headings) (fun index -> index - List.length headings + 1));
  check "long heading anchors are unique"
    (List.length (List.sort_uniq compare (Chat_layout.anchors document))
    = List.length (Chat_layout.rows document));
  let messages = [ message ] in
  let cached = Chat_layout.update cache ~task_id:"task" ~width:32 messages in
  check "same immutable message list reuses full document"
    (Chat_layout.update cache ~task_id:"task" ~width:32 messages == cached);
  let sent = { message with author = "You"; queued = false } in
  let sent_document = Chat_layout.update cache ~task_id:"task" ~width:32 [ sent ] in
  check "short sent header is unchanged"
    ((List.hd (Chat_layout.rows sent_document)).text = "You / sent");
  let unsafe =
    { message with author = "Fixture\255\027\n\194\128agent"; queued = false }
  in
  let unsafe_document = Chat_layout.update cache ~task_id:"task" ~width:40 [ unsafe ] in
  check "author controls and malformed bytes are sanitized before wrapping"
    ((List.hd (Chat_layout.rows unsafe_document)).text = "Fixture�   agent");
  List.iter
    (fun width ->
      let document = Chat_layout.update cache ~task_id:"task" ~width [ message ] in
      check "author rows fit width"
        (List.for_all
           (fun row ->
             Notty.I.width (Notty.I.string Notty.A.empty row.Chat_layout.text) <= width)
           (header document));
      check "queued identity suffix remains complete across reflow"
        (Controller.contains
           (String.concat ""
              (List.map (fun row -> row.Chat_layout.text) (header document)))
           "queued"))
    [ 1; 2; 20; 32; 80 ];
  let empty = { message with author = ""; queued = false } in
  let empty_document = Chat_layout.update cache ~task_id:"task" ~width:20 [ empty ] in
  check "empty author retains a searchable header row"
    ((List.hd (Chat_layout.rows empty_document)).index = 0);
  let tail : Model.message =
    {
      id = "tail";
      author = "Fixture";
      text = String.concat "\n" (List.init 20 (Printf.sprintf "tail %02d"));
      queued = false;
    }
  in
  let old = Chat_layout.update cache ~task_id:"task" ~width:32 [ sent; tail ] in
  let viewport = Chat_viewport.create () in
  let old_rows = Chat_layout.anchors old in
  let rec locate index = function
    | [] -> failwith "body anchor missing"
    | (id, line) :: rest ->
        if id = sent.id && line = 1 then index else locate (index + 1) rest
  in
  let offset = locate 0 old_rows in
  let previous =
    Chat_viewport.update viewport ~task_id:"task" ~rows:old_rows ~height:3
      ~distance:(List.length old_rows - 3 - offset)
      ~seek:None
  in
  let expanded = Chat_layout.update cache ~task_id:"task" ~width:32 [ message; tail ] in
  let view =
    Chat_viewport.update viewport ~task_id:"task"
      ~rows:(Chat_layout.anchors expanded)
      ~height:3 ~distance:previous.distance ~seek:None
  in
  check "author growth preserves paused body anchor"
    (List.nth (Chat_layout.anchors expanded) view.offset = (message.id, 1));
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"author-task" ~title:"Original task" ~repository:"fixture" in
  controller.tasks <- [ { task with messages = [ message ] } ];
  controller.selected <- task.id;
  Controller.act controller (Controller.Focus Conversation);
  Controller.act controller Controller.Zoom;
  let saved = Controller.snapshot controller in
  let frame = Ui.render controller ~width:120 ~height:36 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
  check "UI displays author tail and queued label"
    (Controller.contains (Buffer.contents buffer) "AUTHOR_END"
    && Controller.contains (Buffer.contents buffer) "/ queued");
  Controller.act controller Controller.Begin_chat_search;
  Controller.set_input controller "AUTHOR_END";
  Controller.submit controller;
  ignore (Ui.render controller ~width:120 ~height:36);
  check "search matches full author without changing saved messages"
    (Chat_search.position controller.chat_search = (1, 1)
    && Controller.snapshot controller = saved);
  Printf.printf "Passed %d wrapped author checks. Pure message/layout/input only.\n"
    !checks
