open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let width text = Notty.I.width (Notty.I.string Notty.A.empty text)

let clusters text =
  Uuseg_string.fold_utf_8 `Grapheme_cluster (fun all cluster -> cluster :: all) [] text
  |> List.rev

let () =
  check "empty wrap retains an empty row" (Ui.wrap 5 "" = [ "" ]);
  check "explicit newlines retain blank rows" (Ui.wrap 5 "a\n\nb\n" = [ "a"; ""; "b"; "" ]);
  check "combining accent stays attached at a boundary"
    (Ui.wrap 1 "aéb" = [ "a"; "é"; "b" ]);
  List.iter
    (fun cluster ->
      let columns = max 1 (width cluster) in
      let source = "x" ^ cluster ^ "y" in
      let rows = Ui.wrap columns source in
      check "multi-codepoint grapheme is not divided across rows"
        (List.exists (fun row -> Controller.contains row cluster) rows);
      check "wrapping preserves text bytes" (String.concat "" rows = source);
      check "row boundaries preserve original grapheme sequence"
        (List.concat_map clusters rows = clusters source);
      check "clusters that fit stay within terminal-cell width"
        (List.for_all (fun row -> width row <= columns) rows);
      let narrow = Ui.wrap 1 source in
      check "over-wide grapheme stays whole rather than splitting"
        (List.exists (fun row -> row = cluster) narrow && String.concat "" narrow = source))
    [ "é"; "👍🏽"; "🇺🇸"; "👨‍👩‍👧‍👦"; "1️⃣"; "界" ];
  check "malformed input is normalized before wrapping"
    (Ui.wrap 1 "a\255b" = [ "a"; "�"; "b" ]);
  check "control sequences cannot reach rendered rows"
    (String.concat "" (Ui.wrap 40 "a\027[31mb\t\127") = "a [31mb  ");
  check "word wrapping retains whole accents and emoji"
    (List.concat_map clusters (Ui.wrap_title 2 "aé👍🏽b") = clusters "aé👍🏽b");
  check "word wrap clamps nonpositive widths" (Ui.wrap_title 0 "abc" = [ "a"; "b"; "c" ]);
  check "fitting label has no ellipsis" (Text_layout.ellipsize 6 "hello" = "hello");
  check "overflow label reserves marker width" (Text_layout.ellipsize 4 "hello" = "hel…");
  check "hidden rows mark fitting final text"
    (Text_layout.ellipsize ~more:true 5 "end" = "end…");
  check "one-cell label contains only marker" (Text_layout.ellipsize 1 "hello" = "…");
  check "zero width emits no label" (Text_layout.ellipsize 0 "hello" = "");
  check "row limit marks overflow but keeps prior rows"
    (Text_layout.limit_rows ~width:8 ~height:2 [ "first"; "second"; "third" ]
    = [ "first"; "second…" ]);
  check "exact row limit has no false overflow"
    (Text_layout.limit_rows ~width:8 ~height:2 [ "first"; "second" ]
    = [ "first"; "second" ]);
  check "zero-height limit has no rows"
    (Text_layout.limit_rows ~width:8 ~height:0 [ "first" ] = []);
  List.iter
    (fun cluster ->
      let columns = width cluster + 1 in
      let clipped = Text_layout.ellipsize columns (cluster ^ "extra") in
      check "ellipsis preserves complete leading grapheme"
        (clipped = cluster ^ "…" && width clipped <= columns);
      check "ellipsis never includes partial oversized grapheme"
        (Text_layout.ellipsize 1 (cluster ^ "extra") = "…"))
    [ "é"; "👍🏽"; "🇺🇸"; "👨‍👩‍👧‍👦"; "界" ];
  let controller = Controller.create ~external_events:true () in
  let task = Model.make ~id:"unicode" ~title:"aa👍🏽bb" ~repository:"fixture" in
  controller.tasks <- [ task ];
  controller.selected <- task.id;
  controller.zoom <- true;
  controller.focus <- Controller.Conversation;
  let saved = Controller.snapshot controller in
  List.iter
    (fun (columns, rows) ->
      let frame = Ui.render controller ~width:columns ~height:rows in
      check "Unicode frame remains bounded"
        (Notty.I.width frame.image = columns && Notty.I.height frame.image = rows))
    [ (1, 1); (5, 12); (20, 20); (60, 20); (120, 36) ];
  check "Unicode rendering does not rewrite stored text"
    (Controller.snapshot controller = saved);
  Printf.printf "Passed %d grapheme layout checks. Text and rendering only.\n" !checks
