let width text = Notty.I.width (Notty.I.string Notty.A.empty text)

let text ?(updates = 0) ~width:columns ~selected (task : Model.task) =
  let id = Terminal_text.line task.id and title = Terminal_text.line task.title in
  let title = if updates > 0 then Printf.sprintf "[%d new] %s" updates title else title in
  let title =
    match Task_attention.reason task with
    | None -> title
    | Some reason -> reason ^ " · " ^ title
  in
  let state = Model.label task.state in
  let marker = if selected then " › " else "   " in
  let padded size text = text ^ String.make (max 0 (size - width text)) ' ' in
  let full = marker ^ padded 7 id ^ " " ^ padded 10 state ^ " " ^ title in
  if width full <= columns then full
  else
    let prefix = marker ^ padded 7 id ^ " " ^ padded 10 state ^ " " in
    if width prefix + 4 <= columns then
      prefix ^ Text_layout.ellipsize (columns - width prefix) title
    else
      let state_prefix = marker ^ state ^ " " in
      let remaining = columns - width state_prefix in
      if remaining >= 4 then
        let id_width = min (width id) (max 3 (remaining / 2)) in
        let id = Text_layout.ellipsize id_width id in
        let prefix = state_prefix ^ id ^ " " in
        prefix ^ Text_layout.ellipsize (columns - width prefix) title
      else Text_layout.ellipsize columns (marker ^ state ^ " " ^ id)
