open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let measure () =
  let source =
    List.init 20000 (fun i -> Printf.sprintf "+%06d %s界é" i (String.make 64 'x'))
    |> String.concat "\n"
  in
  let document = Diff_document.parse source in
  let time f =
    let start = Unix.gettimeofday () in
    let result = f () in
    (result, Unix.gettimeofday () -. start)
  in
  let display, prepared = time (fun () -> Diff_display.create document) in
  let rounds = 20 in
  let _, scanned =
    time (fun () ->
        for _ = 1 to rounds do
          ignore
            (Diff_document.fold_lines document ~init:0 ~f:(fun widest text ->
                 let text = Controller.clean ~newlines:false text in
                 max widest (Notty.I.width (Notty.I.string Notty.A.empty text))))
        done)
  in
  let _, visible =
    time (fun () ->
        for _ = 1 to rounds do
          ignore (Diff_display.widest display);
          Diff_display.lines display ~start:10000 ~count:30
          |> List.iter (fun line -> ignore (Notty.I.string Notty.A.empty line))
        done)
  in
  Printf.printf
    "Synthetic patch: %d lines; %d redraw preparations.\n\
     Initial display preparation: %.3f ms\n\
     Repeated full sanitation/width scan: %.3f ms\n\
     Cached width + 30 visible row images: %.3f ms\n\
     Not a whole-TUI or native-GUI benchmark.\n"
    (Diff_document.line_count document)
    rounds (prepared *. 1000.) (scanned *. 1000.) (visible *. 1000.)

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else
    let raw = "diff --git a/example b/example\n+a\t界é\027[31m\n-\255" in
    let document = Diff_document.parse raw in
    let display = Diff_display.create document in
    let lines = Diff_display.lines display ~start:0 ~count:max_int in
    check "display retains line identity and count"
      (List.length lines = Diff_document.line_count document);
    check "display sanitizes controls" (List.nth lines 1 = "+a 界é [31m");
    check "display normalizes malformed UTF-8" (List.nth lines 2 = "-�");
    check "display leaves raw document unchanged"
      (String.concat "\n" (Diff_document.lines document ~start:0 ~count:max_int) = raw);
    let expected =
      List.fold_left
        (fun widest line ->
          max widest (Notty.I.width (Notty.I.string Notty.A.empty line)))
        0 lines
    in
    check "cached width uses terminal cells" (Diff_display.widest display = expected);
    check "display supports bounded visible slice"
      (Diff_display.lines display ~start:1 ~count:1 = [ List.nth lines 1 ]);
    check "negative start clamps to zero"
      (Diff_display.lines display ~start:(-1) ~count:1 = [ List.hd lines ]);
    check "oversized start is empty"
      (Diff_display.lines display ~start:max_int ~count:1 = []);
    check "negative count is empty" (Diff_display.lines display ~start:0 ~count:(-1) = []);
    let empty = Diff_display.create (Diff_document.parse "") in
    check "empty display has zero width and rows"
      (Diff_display.widest empty = 0 && Diff_display.lines empty ~start:0 ~count:10 = []);
    let first = List.hd (Diff_display.lines display ~start:1 ~count:1) in
    check "visible slices reuse prepared strings"
      (List.hd (Diff_display.lines display ~start:1 ~count:1) == first);
    Printf.printf "Passed %d diff display checks. Pure patch data only.\n" !checks
