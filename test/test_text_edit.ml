open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let () =
  let t = Text_edit.create "a界b" in
  check "cursor starts at end" (Text_edit.cursor t = 5);
  let t = Text_edit.left t |> Text_edit.left in
  check "left follows UTF-8 boundaries" (Text_edit.cursor t = 1);
  let t = Text_edit.insert t "é" in
  check "insertion preserves UTF-8" (Text_edit.text t = "aé界b" && Text_edit.cursor t = 3);
  let t = Text_edit.delete t in
  check "delete removes next grapheme" (Text_edit.text t = "aéb");
  let t = Text_edit.backspace t in
  check "backspace removes previous grapheme"
    (Text_edit.text t = "ab" && Text_edit.cursor t = 1);
  let t = Text_edit.home t |> Text_edit.backspace in
  check "backspace at start is safe" (Text_edit.cursor t = 0 && Text_edit.text t = "ab");
  let t = Text_edit.ending t |> Text_edit.right |> Text_edit.delete in
  check "delete at end is safe" (Text_edit.cursor t = 2 && Text_edit.text t = "ab");
  let t = Text_edit.create "abc\n界é\nxyz" |> Text_edit.home |> Text_edit.right in
  check "home moves to current line" (Text_edit.cursor t = 11);
  let t = Text_edit.up t in
  check "up follows grapheme column" (Text_edit.cursor t = 7);
  let t = Text_edit.up t in
  check "up reaches first line" (Text_edit.cursor t = 1);
  let t = Text_edit.up t in
  check "up at top stays" (Text_edit.cursor t = 1);
  let t = Text_edit.down t |> Text_edit.down in
  check "down reaches third line" (Text_edit.cursor t = 11);
  let t = Text_edit.ending t |> Text_edit.down in
  check "down at bottom stays" (Text_edit.cursor t = 13);
  let t = Text_edit.create (String.make 65536 'a') in
  check "insert respects cap" (Text_edit.text (Text_edit.insert t "x") = Text_edit.text t);
  List.iter
    (fun (name, cluster) ->
      let t = Text_edit.create ("a" ^ cluster ^ "b") |> Text_edit.left in
      check (name ^ " left skips whole cluster") (Text_edit.cursor (Text_edit.left t) = 1);
      let at_start = Text_edit.left t in
      check
        (name ^ " right skips whole cluster")
        (Text_edit.cursor (Text_edit.right at_start) = 1 + String.length cluster);
      check
        (name ^ " backspace removes whole cluster")
        (Text_edit.text (Text_edit.backspace t) = "ab");
      check
        (name ^ " delete removes whole cluster")
        (Text_edit.text (Text_edit.delete at_start) = "ab"))
    [
      ("decomposed accent", "é");
      ("multiple marks", "á̧");
      ("skin tone", "👍🏽");
      ("flag", "🇺🇸");
      ("joined family", "👨‍👩‍👧‍👦");
      ("keycap", "1️⃣");
    ];
  let typed =
    Text_edit.create "" |> fun t ->
    Text_edit.insert t "e" |> fun t -> Text_edit.insert t "́"
  in
  check "typed accent joins existing grapheme"
    (Text_edit.text typed = "é" && Text_edit.text (Text_edit.backspace typed) = "");
  let prefix = Text_edit.create "́x" |> Text_edit.home in
  let inserted = Text_edit.insert prefix "a" in
  check "insert before combining mark snaps after merged grapheme"
    (Text_edit.text inserted = "áx" && Text_edit.cursor inserted = String.length "á");
  let joined =
    Text_edit.create "👨👩" |> Text_edit.left |> fun t -> Text_edit.insert t "‍"
  in
  check "insert joiner snaps after joined emoji"
    (Text_edit.cursor joined = String.length "👨‍👩");
  check "joined emoji deletes atomically"
    (Text_edit.text (Text_edit.backspace joined) = "");
  let separated = Text_edit.create "a\ńb" |> Text_edit.home |> Text_edit.left in
  let removed = Text_edit.delete separated in
  check "removing newline repairs merged grapheme cursor"
    (Text_edit.text removed = "áb" && Text_edit.cursor removed = String.length "á");
  let t =
    Text_edit.create "abc\né👍🏽z\nxyz"
    |> Text_edit.home |> Text_edit.right |> Text_edit.right
  in
  let previous = Text_edit.up t in
  check "vertical movement counts graphemes"
    (Text_edit.cursor previous = String.length "abc\né👍🏽");
  let next = Text_edit.down previous in
  check "vertical movement retains grapheme column"
    (Text_edit.cursor next = String.length "abc\né👍🏽z\nxy");
  let crlf = Text_edit.create "a\r\nb" |> Text_edit.home |> Text_edit.left in
  check "CRLF is one movement" (Text_edit.cursor crlf = 1);
  check "CRLF deletes as one grapheme" (Text_edit.text (Text_edit.delete crlf) = "ab");
  let crlf_end =
    Text_edit.create "a\r\nb" |> Text_edit.home |> Text_edit.up |> Text_edit.ending
  in
  check "line ending stays before CRLF" (Text_edit.cursor crlf_end = 1);
  let invalid = Text_edit.create "a\255b" in
  check "malformed UTF-8 normalized" (Text_edit.text invalid = "a�b");
  check "malformed insertion normalized"
    (Text_edit.text (Text_edit.insert (Text_edit.create "") "\255") = "�");
  let controller = Controller.create ~external_events:true () in
  Controller.act controller (Controller.Select "T-101");
  Controller.act controller Controller.Begin_compose;
  Controller.insert_text controller "first";
  Controller.key controller (`ASCII 'l', [ `Ctrl ]);
  Controller.insert_text controller "second";
  check "newline shortcut retains draft"
    (Controller.draft controller = "first\nsecond"
    && controller.input = Controller.Compose);
  Controller.key controller (`Arrow `Left, []);
  Controller.insert_text controller "!";
  check "composer inserts at cursor" (Controller.draft controller = "first\nsecon!d");
  Controller.paste_key controller (`Enter, []);
  Controller.paste_key controller (`ASCII 'q', []);
  check "paste newline never submits or quits"
    (Controller.draft controller = "first\nsecon!\nqd"
    && (not controller.quit)
    && controller.input = Controller.Compose);
  let saved =
    Controller.snapshot controller |> Snapshot.encode |> Snapshot.decode |> Result.get_ok
  in
  let restored = Controller.create ~external_events:true () in
  Controller.restore restored saved;
  check "snapshot restores multiline draft"
    (Controller.draft restored = "first\nsecon!\nqd");
  Controller.key controller (`Escape, []);
  Controller.act controller Controller.Begin_compose;
  check "reopen keeps multiline draft" (Controller.draft controller = "first\nsecon!\nqd");
  Controller.key controller (`Enter, []);
  check "send retains multiline message"
    ((List.hd (List.rev (Option.get (Controller.selected controller)).messages)).text
   = "first\nsecon!\nqd");
  Controller.act controller Controller.Begin_search;
  Controller.paste_key controller (`Enter, []);
  check "search paste normalizes newline"
    (controller.query = " " && controller.input = Controller.Search);
  Controller.key controller (`Escape, []);
  Controller.act controller Controller.Begin_compose;
  Controller.set_input controller "";
  let parser = Notty.Unescape.create () in
  let bytes = Bytes.of_string "one\ntwo" in
  Notty.Unescape.input parser bytes 0 (Bytes.length bytes);
  let rec drain () =
    match Notty.Unescape.next parser with
    | `Key key ->
        Controller.paste_key controller key;
        drain ()
    | `Await | `End -> ()
    | _ -> drain ()
  in
  drain ();
  check "LF paste preserves newline" (Controller.draft controller = "one\ntwo");
  Controller.set_input controller "";
  let parser = Notty.Unescape.create () in
  let bytes = Bytes.of_string "\012" in
  Notty.Unescape.input parser bytes 0 (Bytes.length bytes);
  (match Notty.Unescape.next parser with
  | `Key key -> Controller.key controller key
  | _ -> failwith "Missing newline key");
  check "terminal newline key decoded" (Controller.draft controller = "\n");

  Controller.set_input controller "";
  List.iter (fun text -> Controller.insert_text controller text) [ "e"; "́"; "👍"; "🏽" ];
  Controller.key controller (`Backspace, []);
  check "composer backspace deletes entire skin-tone emoji"
    (Controller.draft controller = "é");
  Controller.key controller (`Backspace, []);
  check "composer backspace deletes entire decomposed accent"
    (Controller.draft controller = "");
  Controller.insert_text controller "a🇺🇸b";
  Controller.key controller (`Arrow `Left, []);
  Controller.key controller (`Arrow `Left, []);
  Controller.key controller (`Delete, []);
  check "composer delete handles flag as one unit" (Controller.draft controller = "ab");
  Printf.printf "Passed %d text editing checks.\n" !checks
