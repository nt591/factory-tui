open Factory_tui
open Controller

let check name condition = if not condition then failwith name

let () =
  List.iter
    (fun (width, height) ->
      let t = Controller.create ~external_events:true () in
      t.focus <- Board;
      let render () =
        let frame = Ui.render t ~width ~height in
        let buffer = Buffer.create 8192 in
        Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
        (frame, String.split_on_char '\n' (Buffer.contents buffer))
      in
      let initial, _ = render () in
      let saved = Controller.snapshot t and selected = t.selected in
      List.iter
        (fun focus ->
          check "Tab focuses the next section" (t.focus = focus);
          let frame, rows = render () in
          check "Tab preserves pane positions" (frame.panes = initial.panes);
          List.iter
            (fun ((r : Ui.rect), pane) ->
              let row = List.nth rows r.y in
              let glyphs = Ui.wrap 1 row in
              check "only the active section has a heavy boundary"
                (List.nth glyphs r.x = if pane = focus then "┏" else "╭"))
            frame.panes;
          check "all lanes are inside the whole board boundary"
            (let board, _ = List.find (fun (_, focus) -> focus = Board) frame.panes in
             List.for_all
               (fun ((r : Ui.rect), _, _, _) ->
                 r.x > board.x && r.y > board.y
                 && r.x + r.w < board.x + board.w
                 && r.y + r.h < board.y + board.h)
               frame.columns);
          check "focus preserves the task and persisted state"
            (t.selected = selected && Controller.snapshot t = saved);
          Controller.key t (`Tab, []))
        [ Board; Conversation; Activity; Board ];
      Controller.key t (`Tab, [ `Shift ]);
      check "Shift-Tab reverses section navigation" (t.focus = Board);
      let frame, _ = render () in
      let board, _ = List.find (fun (_, focus) -> focus = Board) frame.panes in
      Controller.act t (Focus Conversation);
      Ui.mouse t frame ~now:1. (`Press `Left, (board.x + 2, board.y), []);
      check "board title is clickable for focus" (t.focus = Board);
      check "focus starts no creation or execution"
        (t.creation_request = None && t.creation_job = None
        && Controller.snapshot t = saved))
    [ (120, 36); (240, 50) ];
  Printf.printf "Passed section focus, stable geometry and board boundary checks.\n"
