let width text = Notty.I.width (Notty.I.string Notty.A.empty text)

let render ~width:columns ~label ~hint editor =
  if columns <= 0 then ""
  else
    let text = Text_edit.text editor and cursor = Text_edit.cursor editor in
    let before = Terminal_text.line (String.sub text 0 cursor)
    and after =
      Terminal_text.line (String.sub text cursor (String.length text - cursor))
    in
    let label = Terminal_text.line label and hint = Terminal_text.line hint in
    let complete = label ^ before ^ "▏" ^ after ^ hint in
    if width complete <= columns then complete
    else
      (* Long values take priority over hints so the edit cursor remains visible. *)
      let label = Text_layout.ellipsize (min (width label) (columns / 2)) label in
      label ^ Text_layout.cursor_window (columns - width label) ~before ~after
