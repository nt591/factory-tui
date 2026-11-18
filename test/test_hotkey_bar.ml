open Factory_tui

let () =
  List.iter
    (fun label ->
      let image = Hotkey_bar.action label in
      assert (Notty.I.width image = String.length label + 2);
      let buffer = Buffer.create 256 in
      Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (Notty.I.width image, 1) image;
      assert (Controller.contains (Buffer.contents buffer) label))
    [ "e expand"; "b session board"; "[Send reply / Enter]"; "[Close / Esc]" ];
  List.iter
    (fun width ->
      let image = Hotkey_bar.hints ~width "hjkl: cards · Tab: panes · ?: help" in
      assert (Notty.I.width image = width))
    [ 1; 20; 60; 120 ];
  print_endline "Passed grouped hotkey rendering checks. Pure terminal images."
