open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let reference ~newlines text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ decoded ->
      match decoded with
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code = 10 && newlines then Buffer.add_char buffer '\n'
          else if code < 32 || (code >= 127 && code <= 159) then
            Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let () =
  let control_buffer = Buffer.create 256 in
  for code = 0 to 159 do
    Uutf.Buffer.add_utf_8 control_buffer (Uchar.of_int code)
  done;
  let controls = Buffer.contents control_buffer in
  let expected =
    String.make 32 ' ' ^ String.init 95 (fun i -> Char.chr (i + 32)) ^ String.make 33 ' '
  in
  check "single-line policy replaces all terminal control ranges"
    (Terminal_text.line controls = expected);
  let multiline = Bytes.of_string expected in
  Bytes.set multiline 10 '\n';
  check "multiline policy retains only LF from controls"
    (Terminal_text.multiline controls = Bytes.to_string multiline);
  check "CRLF retains the existing space plus newline policy"
    (Terminal_text.multiline "a\r\nb" = "a \nb");
  check "single-line CRLF becomes two spaces" (Terminal_text.line "a\r\nb" = "a  b");
  let unicode = "é é 👩🏽‍💻 Ελληνικά 中文 \226\128\168 \226\128\169" in
  check "printable Unicode and grapheme sequences stay exact"
    (Terminal_text.line unicode = unicode && Terminal_text.multiline unicode = unicode);
  check "escape sequences cannot reach terminal as controls"
    (Terminal_text.line "\027[31mtext\027[0m" = " [31mtext [0m");
  let corpus =
    [
      "";
      "\255";
      "a\192\175b";
      "\237\160\128";
      "\240\159";
      "\128\129\255";
      "title\027\194\128\nbody";
    ]
  in
  let check_input input =
    List.iter
      (fun (newlines, fn) ->
        let output = fn input in
        check "sanitation matches existing decode/control policy"
          (output = reference ~newlines input);
        check "sanitation is idempotent" (fn output = output);
        check "output decodes without malformed UTF8"
          (Uutf.String.fold_utf_8
             (fun valid _ -> function `Malformed _ -> false | `Uchar _ -> valid)
             true output))
      [ (false, Terminal_text.line); (true, Terminal_text.multiline) ]
  in
  List.iter check_input corpus;
  let random = Random.State.make [| 42; 73 |] in
  for _ = 1 to 2000 do
    check_input
      (String.init (Random.State.int random 128) (fun _ ->
           Char.chr (Random.State.int random 256)))
  done;
  let printable = Buffer.create 4096 in
  for code = 160 to 65535 do
    if Uchar.is_valid code then Uutf.Buffer.add_utf_8 printable (Uchar.of_int code)
  done;
  let printable = Buffer.contents printable in
  check "all printable BMP scalar encodings stay exact"
    (Terminal_text.line printable = printable);
  let editor = Text_edit.create "\027\nvalue" in
  let original = Text_edit.text editor and cursor = Text_edit.cursor editor in
  ignore (Terminal_text.line original);
  ignore (Terminal_text.multiline original);
  check "display sanitation does not mutate editor text or cursor"
    (Text_edit.text editor = original && Text_edit.cursor editor = cursor);
  check "Controller compatibility entry point retains both policies"
    (Controller.clean "a\027\nb" = Terminal_text.multiline "a\027\nb"
    && Controller.clean ~newlines:false "a\027\nb" = Terminal_text.line "a\027\nb");
  Printf.printf "Passed %d shared terminal-text checks. Pure bytes and Unicode only.\n"
    !checks
