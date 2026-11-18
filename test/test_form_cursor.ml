open Factory_tui

let check name condition = if not condition then failwith name

let () =
  check "end cursor follows text suffix"
    (Text_layout.cursor_window 8 ~before:"prefix-END" ~after:"" = "fix-END▏");
  check "home cursor reveals prefix"
    (Text_layout.cursor_window 8 ~before:"" ~after:"BEGIN-long" = "▏BEGIN-l");
  check "middle cursor retains editable neighborhood"
    (Text_layout.cursor_window 8 ~before:"abc" ~after:"defghijk" = "abc▏defg");
  check "long middle edit retains text on both sides of cursor"
    (Text_layout.cursor_window 10 ~before:"long-prefix" ~after:"suffix" = "prefix▏suf");
  check "short forward context gives unused space to preceding text"
    (Text_layout.cursor_window 10 ~before:"long-prefix" ~after:"z" = "g-prefix▏z");
  check "end editing uses full width for preceding context"
    (Text_layout.cursor_window 10 ~before:"long-prefix" ~after:"" = "ng-prefix▏");

  List.iter
    (fun cluster ->
      let text =
        Text_layout.cursor_window 5 ~before:("prefix" ^ cluster) ~after:"suffix"
      in
      check "cursor window cannot split graphemes"
        (Notty.I.width (Notty.I.string Notty.A.empty text) <= 5
        && Controller.contains text "▏"))
    [ "é"; "👍🏽"; "🇺🇸"; "界" ];
  check "decomposed accent remains attached beside cursor"
    (Text_layout.cursor_window 2 ~before:"long-é" ~after:"tail" = "é▏");
  check "oversized grapheme is omitted whole to keep cursor visible"
    (Text_layout.cursor_window 1 ~before:"👍🏽" ~after:"界" = "▏");
  let form =
    Workspace_form.create
      ~source:("/BEGIN/" ^ String.make 160 'x' ^ "/END")
      ~parent:"/tasks" ~revision:"@" ~model:"fixture" ()
  in
  let original = Workspace_form.value form Workspace_form.Source in
  let render () =
    let view =
      Workspace_dialog.render form ~busy:false ~status:"fixture" ~width:60 ~height:26
    in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (60, 26) view.image;
    Buffer.contents buffer
  in
  check "long source field exposes end cursor" (Controller.contains (render ()) "/END▏");
  Workspace_form.key form (`Home, []);
  check "Home exposes editable start instead of right-aligned suffix"
    (Controller.contains (render ()) "▏/BEGIN/");
  Workspace_form.key form (`Arrow `Right, []);
  Workspace_form.key form (`ASCII 'Z', []);
  check "editing visible prefix changes exact cursor position"
    (String.starts_with ~prefix:"/ZBEGIN/"
       (Workspace_form.value form Workspace_form.Source)
    && Controller.contains (render ()) "/Z▏BEGIN/");
  Workspace_form.key form (`End, []);
  check "End restores suffix viewport" (Controller.contains (render ()) "/END▏");
  List.iter (fun _ -> Workspace_form.key form (`Arrow `Left, [])) [ 1; 2; 3 ];
  check "long workspace field exposes upcoming suffix beside cursor"
    (Controller.contains (render ()) "/▏END");

  check "viewport does not truncate stored source"
    (String.length (Workspace_form.value form Workspace_form.Source)
    = String.length original + 1);
  Printf.printf "Passed workspace cursor-window checks. Pure text/form rendering only.\n"
