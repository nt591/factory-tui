open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let message id text : Model.message = { id; text; author = "You"; queued = true }

let measure () =
  let messages =
    List.init 2000 (fun i -> message (string_of_int i) (String.make 120 'x' ^ "é👍🏽"))
  in
  let cache = Chat_layout.create () in
  let run () = Chat_layout.update cache ~task_id:"task" ~width:76 messages in
  let document = run () in
  let time fn =
    let start = Unix.gettimeofday () in
    fn ();
    Unix.gettimeofday () -. start
  in
  let uncached =
    time (fun () ->
        for _ = 1 to 20 do
          Chat_layout.clear cache;
          ignore (run ())
        done)
  in
  let cached =
    time (fun () ->
        for _ = 1 to 20 do
          ignore (run ())
        done)
  in
  let stream_messages round =
    List.mapi
      (fun index (message : Model.message) ->
        if index = 1999 then { message with text = message.text ^ string_of_int round }
        else message)
      messages
  in
  let updates = List.init 20 stream_messages in
  let rebuilt_stream =
    time (fun () ->
        List.iter
          (fun messages ->
            Chat_layout.clear cache;
            ignore (Chat_layout.update cache ~task_id:"task" ~width:76 messages))
          updates)
  in
  Chat_layout.clear cache;
  ignore (run ());
  let reused_stream =
    time (fun () ->
        List.iter
          (fun messages ->
            ignore (Chat_layout.update cache ~task_id:"task" ~width:76 messages))
          updates)
  in
  Printf.printf
    "Twenty single-message updates, full rebuild: %.3f ms; reused unchanged blocks: %.3f \
     ms.\n"
    (rebuilt_stream *. 1000.) (reused_stream *. 1000.);
  Printf.printf
    "Synthetic transcript: 2000 messages, %d rows, 20 layout passes.\n\
     Rebuilt wrapped rows and anchors: %.3f ms\n\
     Unchanged cached layout: %.6f ms\n\
     Excludes search, viewport scans, image construction, terminal output.\n"
    (List.length (Chat_layout.rows document))
    (uncached *. 1000.) (cached *. 1000.)

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else
    let cache = Chat_layout.create () in
    let messages = [ message "first" "abcde"; message "second" "é👍🏽\nlast" ] in
    let update ?(task_id = "task") ?(width = 3) messages =
      Chat_layout.update cache ~task_id ~width messages
    in
    let first = update messages in
    check "identical list and width reuse document" (update messages == first);
    check "anchor count matches display rows"
      (List.length (Chat_layout.anchors first) = List.length (Chat_layout.rows first));
    check "body anchors retain wrapped row identity"
      (List.mem ("first", 1) (Chat_layout.anchors first)
      && List.mem ("first", 2) (Chat_layout.anchors first));
    check "queued header preserves delivery label"
      (String.concat ""
         (List.filter_map
            (fun (row : Chat_layout.row) ->
              if row.id = "first" && row.tone = Author true then Some row.text else None)
            (Chat_layout.rows first))
      = "You/queued");
    let resized = update ~width:20 messages in
    check "width changes rebuild wrapping"
      (resized != first
      && List.length (Chat_layout.rows resized) < List.length (Chat_layout.rows first));
    check "resized layout is cached" (update ~width:20 messages == resized);
    let changed =
      List.map
        (fun (m : Model.message) ->
          if m.id = "first" then { m with text = "new streamed body"; queued = false }
          else m)
        messages
    in
    let streamed = update ~width:20 changed in
    let row document id =
      List.find
        (fun (r : Chat_layout.row) -> r.id = id && r.index = 1)
        (Chat_layout.rows document)
    in
    check "unchanged message rows survive streamed replacement by identity"
      (row streamed "second" == row resized "second");
    check "changed message rows are rebuilt" (row streamed "first" != row resized "first");
    check "unchanged message anchors are reused"
      (List.find
         (fun (id, index) -> id = "second" && index = 1)
         (Chat_layout.anchors streamed)
      == List.find
           (fun (id, index) -> id = "second" && index = 1)
           (Chat_layout.anchors resized));
    let reordered = update ~width:20 (List.rev changed) in
    check "message reorder follows current transcript, not cached order"
      ((List.hd (Chat_layout.rows reordered)).id = "second"
      && row reordered "second" == row streamed "second");
    let removed = update ~width:20 [ List.hd changed ] in
    check "removed message leaves rows and anchors"
      (List.for_all
         (fun (r : Chat_layout.row) -> r.id = "first")
         (Chat_layout.rows removed)
      && List.for_all (fun (id, _) -> id = "first") (Chat_layout.anchors removed));
    let restored = update ~width:20 changed in
    check "removed message block is discarded rather than retained"
      (row restored "second" != row streamed "second");
    let renamed_author =
      List.map
        (fun (m : Model.message) ->
          if m.id = "second" then { m with author = "Factory" } else m)
        changed
    in
    let author_layout = update ~width:20 renamed_author in
    check "same ID with changed author rebuilds header"
      (List.exists
         (fun (r : Chat_layout.row) ->
           r.id = "second" && r.index = 0 && r.text = "Factory / queued")
         (Chat_layout.rows author_layout));

    check "streamed message rebuilds same task layout" (streamed != resized);
    check "acknowledgement rebuilds header"
      ((List.hd (Chat_layout.rows streamed)).text = "You / sent");
    check "replacement text appears and old text disappears"
      (List.exists
         (fun (r : Chat_layout.row) -> r.text = "new streamed body")
         (Chat_layout.rows streamed)
      && not
           (List.exists
              (fun (r : Chat_layout.row) -> r.text = "abcde")
              (Chat_layout.rows streamed)));
    let other = update ~task_id:"other" ~width:20 changed in
    check "task identity invalidates cache" (other != streamed);
    Chat_layout.clear cache;
    check "clear discards retained document"
      (update ~task_id:"other" ~width:20 changed != other);
    let unsafe = update ~width:30 [ message "unsafe" "a\255\027b\nnext" ] in
    check "cached body sanitizes malformed UTF-8 and controls"
      (List.exists
         (fun (r : Chat_layout.row) -> r.text = "a� b")
         (Chat_layout.rows unsafe));
    check "newlines preserve logical body rows"
      (List.exists
         (fun (r : Chat_layout.row) -> r.text = "next")
         (Chat_layout.rows unsafe));
    let empty = update [] in
    check "empty transcript has no rows or anchors"
      (Chat_layout.rows empty = [] && Chat_layout.anchors empty = []);
    let copied = List.map (fun (m : Model.message) -> { m with text = m.text }) changed in
    let doc = update changed in
    check "structurally equal replacement list rebuilds safely" (update copied != doc);
    let rolling_cache = Chat_layout.create () in
    let rolling =
      ref (List.init 30 (fun index -> message (string_of_int index) "Old é👍🏽 body"))
    in
    for update_index = 0 to 59 do
      let target = string_of_int (update_index mod 30) in
      rolling :=
        List.map
          (fun (message : Model.message) ->
            if message.id = target then
              {
                message with
                text =
                  Printf.sprintf "Stream %d\n%s" update_index
                    (String.make (update_index + 1) 'x');
                queued = update_index mod 2 = 0;
                author = (if update_index mod 3 = 0 then "Codex" else "You");
              }
            else message)
          !rolling;
      if update_index mod 7 = 0 then rolling := List.rev !rolling;
      let task_id = if update_index < 45 then "first-task" else "next-task" in
      let width = if update_index < 30 then 20 else 35 in
      let incremental = Chat_layout.update rolling_cache ~task_id ~width !rolling in
      let full = Chat_layout.update (Chat_layout.create ()) ~task_id ~width !rolling in
      check
        "incremental stream layout equals a fresh layout after text/label/order/width \
         changes"
        (Chat_layout.rows incremental = Chat_layout.rows full
        && Chat_layout.anchors incremental = Chat_layout.anchors full)
    done;
    let controller = Controller.create ~external_events:true () in
    let task = Model.make ~id:"rendered" ~title:"Cached prompt" ~repository:"fixture" in
    controller.tasks <- [ task ];
    controller.selected <- task.id;
    controller.zoom <- true;
    controller.focus <- Controller.Conversation;
    let saved = Controller.snapshot controller in
    ignore (Ui.render controller ~width:120 ~height:36);
    let before =
      Chat_layout.update controller.chat_layout ~task_id:task.id ~width:76 task.messages
    in
    ignore (Ui.render controller ~width:120 ~height:36);
    check "renderer reuses its prepared transcript"
      (Chat_layout.update controller.chat_layout ~task_id:task.id ~width:76 task.messages
      == before);
    let changed_task =
      { task with model = "new-next-model"; revision = task.revision + 1 }
    in
    controller.tasks <- [ changed_task ];
    ignore (Ui.render controller ~width:120 ~height:36);
    check "non-message settings change does not invalidate transcript"
      (Chat_layout.update controller.chat_layout ~task_id:task.id ~width:76
         changed_task.messages
      == before);
    controller.tasks <- [ task ];
    ignore (Ui.render controller ~width:120 ~height:50);
    check "height-only resize reuses prepared transcript"
      (Chat_layout.update controller.chat_layout ~task_id:task.id ~width:76 task.messages
      == before);
    check "transient layout state never enters persistence"
      (Controller.snapshot controller = saved);
    Printf.printf "Passed %d chat layout checks. Pure transcript data only.\n" !checks
