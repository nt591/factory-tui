open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let make ?(archive = false) ?repository ?(count = 7) ?(query = "") width =
    Board_summary.make ~width ~archive ~repository ~count ~query
  in
  check "short summary preserves familiar layout"
    ((make 120).text = " Session board  |  7 tasks  | / search tasks");
  let long = make ~repository:(String.make 180 'r') ~query:(String.make 180 'q') 60 in
  check "long values keep actual count visible" (Controller.contains long.text "7 tasks");
  check "long values keep search action visible"
    (List.exists (fun (hit : Board_summary.hit) -> hit.action = Search) long.hits
    && Controller.contains long.text "/ ");
  let archive = make ~archive:true ~query:(String.make 180 'q') 60 in
  check "archive retains accepted count and view name"
    (Controller.contains archive.text "Archive"
    && Controller.contains archive.text "7 tasks accepted");
  let invalid = make ~repository:"repo\255\027\n" ~query:"query\255\027\n" 120 in
  check "invalid text sanitized before widths"
    (Controller.contains invalid.text "repo�  "
    && Controller.contains invalid.text "query�  ");
  List.iter
    (fun width ->
      List.iter
        (fun archive ->
          let summary =
            make ~archive ~repository:"équipe/long-repository-label"
              ~query:(String.make 200 'q') width
          in
          check "summary width bounded"
            (Notty.I.width (Notty.I.string Notty.A.empty summary.text) <= max 0 width);
          check "summary targets match rendered extent"
            (List.for_all
               (fun (hit : Board_summary.hit) ->
                 hit.x >= 0 && hit.width > 0
                 && hit.x + hit.width
                    <= Notty.I.width (Notty.I.string Notty.A.empty summary.text))
               summary.hits);
          check "search target starts at displayed slash"
            (List.for_all
               (fun (hit : Board_summary.hit) ->
                 if hit.action <> Search then true
                 else
                   let cells =
                     List.rev
                       (Uuseg_string.fold_utf_8 `Grapheme_cluster
                          (fun cells cell -> cell :: cells)
                          [] summary.text)
                   in
                   List.nth cells hit.x = "/")
               summary.hits);
          check "targets never overlap"
            (match summary.hits with [ a; b ] -> a.x + a.width <= b.x | _ -> true))
        [ false; true ])
    [ -1; 0; 1; 10; 20; 30; 40; 60; 120 ];
  let controller = Controller.create ~external_events:true () in
  let repo = "/very/long/" ^ String.make 180 'p' ^ "/project" in
  let task = Model.make ~id:"summary" ~title:(String.make 150 'q') ~repository:repo in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.repository <- Some repo;
  controller.query <- String.make 150 'q';
  let saved = Controller.snapshot controller in
  let render width height = Ui.render controller ~width ~height in
  let frame = render 60 23 in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 23) frame.image;
  let row = List.nth (String.split_on_char '\n' (Buffer.contents buffer)) 2 in
  check "UI uses repository suffix and filtered count"
    (Controller.contains row "project" && Controller.contains row "1 tasks");
  let header_hits = List.filter (fun (hit : Ui.hit) -> hit.rect.y = 2) frame.hits in
  let archive =
    List.find (fun (hit : Ui.hit) -> hit.action = Controller.Toggle_archive) header_hits
  in
  Ui.mouse controller frame ~now:0. (`Press `Left, (archive.rect.x, 2), []);
  check "label click toggles only board archive view"
    (controller.archive
    && controller.repository = Some repo
    && (Controller.snapshot controller).tasks = saved.tasks
    && (Controller.snapshot controller).drafts = saved.drafts);
  let frame = render 60 23 in
  let search =
    List.find
      (fun (hit : Ui.hit) -> hit.rect.y = 2 && hit.action = Controller.Begin_search)
      frame.hits
  in
  Ui.mouse controller frame ~now:1. (`Press `Left, (search.rect.x, 2), []);
  check "search click edits exact unchanged query"
    (controller.input = Search && Text_edit.text controller.editor = String.make 150 'q');
  Controller.key controller (`Escape, []);
  controller.help <- true;
  let modal = render 60 23 in
  check "modal hides all summary targets"
    (List.for_all
       (fun (hit : Ui.hit) ->
         hit.action <> Controller.Begin_search && hit.action <> Controller.Toggle_archive)
       modal.hits);
  controller.help <- false;
  List.iter
    (fun (width, height) ->
      let frame = render width height in
      check "tiny summary targets stay bounded"
        (List.for_all
           (fun (hit : Ui.hit) ->
             let r = hit.rect in
             r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height)
           frame.hits))
    [ (1, 1); (20, 8); (60, 23); (120, 36); (180, 50) ];
  Printf.printf "Passed %d board summary checks. Pure layout/input only.\n" !checks
