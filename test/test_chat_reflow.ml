open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let source = "abcde\n\n👩🏽‍💻éZ\n" in
  let positions = Text_layout.wrap_positions 3 source in
  check "positioned wrapping retains ordinary wrap output"
    (List.map snd positions = Text_layout.wrap 3 source);
  check "positioned wrap tracks newline and grapheme bytes"
    (List.map fst positions = [ 0; 3; 6; 7; 22; 27 ]);
  check "empty input has one row at zero" (Text_layout.wrap_positions 10 "" = [ (0, "") ]);
  let cache = Chat_layout.create () in
  let viewport = Chat_viewport.create () in
  let text = String.concat " " (List.init 200 (Printf.sprintf "word%03d")) in
  let message : Model.message = { id = "long"; author = "Agent"; text; queued = false } in
  let tail : Model.message =
    { id = "tail"; author = "Agent"; text = String.make 1000 't'; queued = false }
  in
  let messages = [ message; tail ] in
  let document width = Chat_layout.update cache ~task_id:"task" ~width messages in
  let original = document 40 in
  let rows = Chat_layout.anchors original in
  let target = 11 in
  let anchored_byte = snd (List.nth rows target) in
  let first =
    Chat_viewport.update viewport ~task_id:"task" ~rows ~height:5
      ~distance:(List.length rows - 5 - target)
      ~seek:None
  in
  check "initial reading anchor is within long body"
    (first.offset = target && anchored_byte > 1);
  let distance = ref first.distance in
  List.iter
    (fun width ->
      let document = document width in
      let rows = Chat_layout.anchors document in
      let view =
        Chat_viewport.update viewport ~task_id:"task" ~rows ~height:5 ~distance:!distance
          ~seek:None
      in
      distance := view.distance;
      let id, offset = List.nth rows view.offset in
      let next = List.nth rows (view.offset + 1) in
      check "resize keeps original body position in first visible row"
        (id = "long" && offset <= anchored_byte
        && (fst next <> "long" || snd next > anchored_byte));
      if width = 40 then
        check "return to original width restores exact row" (view.offset = target))
    [ 76; 23; 100; 12; 40; 76; 40 ];
  let grown = { tail with text = tail.text ^ String.make 500 't' } in
  let document = Chat_layout.update cache ~task_id:"task" ~width:40 [ message; grown ] in
  let followed =
    Chat_viewport.update viewport ~task_id:"task"
      ~rows:(Chat_layout.anchors document)
      ~height:5 ~distance:!distance ~seek:None
  in
  check "later stream growth preserves precise reading position" (followed.offset = target);
  let resized =
    Chat_viewport.update viewport ~task_id:"task"
      ~rows:(Chat_layout.anchors document)
      ~height:10 ~distance:followed.distance ~seek:None
  in
  check "height change preserves same body anchor" (resized.offset = target);
  let latest =
    Chat_viewport.update viewport ~task_id:"task"
      ~rows:(Chat_layout.anchors document)
      ~height:10 ~distance:0 ~seek:None
  in
  check "explicit latest still follows after reflow" latest.following;
  let unicode : Model.message = { message with text = "start\n👩🏽‍💻 é 中文\nend" } in
  let unicode_document =
    Chat_layout.update cache ~task_id:"unicode" ~width:2 [ unicode ]
  in
  let anchors = Chat_layout.anchors unicode_document in
  check "Unicode body anchor positions remain distinct"
    (List.length (List.sort_uniq compare anchors) = List.length anchors);
  check "spacer anchor follows sanitized message bytes"
    (List.hd (List.rev anchors) = (unicode.id, String.length unicode.text + 2));
  let random = Random.State.make [| 27 |] in
  for _ = 1 to 100 do
    let source =
      String.concat ""
        (List.init 100 (fun _ ->
             List.nth [ "a"; "é"; "👩🏽‍💻"; "中"; "\n"; " " ] (Random.State.int random 6)))
    in
    let width = 1 + Random.State.int random 60 in
    let positioned = Text_layout.wrap_positions width source in
    check "row starts are strictly increasing across grapheme wrapping"
      (let rec sorted = function
         | [] | [ _ ] -> true
         | (a, _) :: ((b, _) :: _ as rest) -> a < b && sorted rest
       in
       sorted positioned);
    check "each positioned row names original source text"
      (List.for_all
         (fun (offset, row) -> String.sub source offset (String.length row) = row)
         positioned)
  done;
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"reflow" ~title:"Initial instruction" ~repository:"fixture" in
  controller.tasks <- [ { task with messages } ];
  controller.selected <- task.id;
  Controller.act controller (Controller.Focus Conversation);
  Controller.act controller Controller.Zoom;
  ignore (Ui.render controller ~width:120 ~height:36);
  Controller.key controller (`Home, []);
  for _ = 1 to 6 do
    Controller.key controller (`ASCII 'j', [])
  done;
  let initial = Ui.render controller ~width:120 ~height:36 in
  let saved = Controller.snapshot controller in
  List.iter
    (fun width -> ignore (Ui.render controller ~width ~height:36))
    [ 90; 160; 84; 120 ];
  let restored = Ui.render controller ~width:120 ~height:36 in
  check "UI width changes do not alter saved messages or drafts"
    (Controller.snapshot controller = saved);
  check "UI width round trip restores transcript image" (initial.image = restored.image);
  Printf.printf "Passed %d precise chat reflow checks. Pure Unicode/layout only.\n"
    !checks
