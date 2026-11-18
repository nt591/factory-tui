open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  check "short query retains familiar banner"
    (Search_banner.text ~width:80 ~query:"line" ~editing:false ~position:1 ~count:2
    = " /chat line · 1/2 messages · n/N matches");
  List.iter
    (fun columns ->
      let text =
        Search_banner.text ~width:columns ~query:(String.make 180 'q') ~editing:true
          ~position:2 ~count:5
      in
      check "long-query banner fits its pane"
        (Notty.I.width (Notty.I.string Notty.A.empty text) <= columns);
      check "long query cannot hide match count and navigation"
        (Controller.contains text "2/5" && Controller.contains text "n/N"))
    [ 20; 36; 56; 76 ];
  check "zero-width banner is empty"
    (Search_banner.text ~width:0 ~query:"anything" ~editing:true ~position:0 ~count:0 = "");
  let clean =
    Search_banner.text ~width:100 ~query:"a\255\027\194\128b" ~editing:false ~position:0
      ~count:0
  in
  check "banner safely renders malformed text and controls"
    (Controller.contains clean "a�  b");
  let query = "BEGIN-" ^ String.make 180 'x' ^ "-END" in
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"search-task" ~title:query ~repository:"fixture" in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.zoom <- true;
  Controller.act controller Controller.Begin_chat_search;
  Controller.set_input controller query;
  Controller.submit controller;
  let saved = Controller.snapshot controller in
  let frame = Ui.render controller ~width:60 ~height:20 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 20) frame.image;
  let text = Buffer.contents buffer in
  check "actual compact long-query search keeps result count visible"
    (Controller.contains text "1/1 messages · n/N");
  check "display abbreviation does not shorten search query"
    (Chat_search.query controller.chat_search = query);
  check "matching and task data remain unchanged"
    (Chat_search.position controller.chat_search = (1, 1)
    && Controller.snapshot controller = saved);
  Controller.key controller (`ASCII 'n', []);
  ignore (Ui.render controller ~width:60 ~height:20);
  check "long-query navigation never creates a task or run"
    (List.length controller.tasks = 1
    && (Option.get (Controller.selected controller)).active = None);
  Printf.printf "Passed %d long-query banner checks. Pure search/rendering only.\n"
    !checks
