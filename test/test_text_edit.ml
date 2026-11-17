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
  check "delete removes next codepoint" (Text_edit.text t = "aéb");
  let t = Text_edit.backspace t in
  check "backspace removes previous codepoint"
    (Text_edit.text t = "ab" && Text_edit.cursor t = 1);
  let t = Text_edit.home t |> Text_edit.backspace in
  check "backspace at start is safe" (Text_edit.cursor t = 0 && Text_edit.text t = "ab");
  let t = Text_edit.ending t |> Text_edit.right |> Text_edit.delete in
  check "delete at end is safe" (Text_edit.cursor t = 2 && Text_edit.text t = "ab");
  let t = Text_edit.create "abc\n界é\nxyz" |> Text_edit.home |> Text_edit.right in
  check "home moves to current line" (Text_edit.cursor t = 11);
  let t = Text_edit.up t in
  check "up follows codepoint column" (Text_edit.cursor t = 7);
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

  Printf.printf "Passed %d text editing checks.\n" !checks
