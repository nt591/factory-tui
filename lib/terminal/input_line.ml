let clean value =
  let buffer = Buffer.create (String.length value) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code < 32 || (code >= 127 && code <= 159) then Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () value;
  Buffer.contents buffer

let width text = Notty.I.width (Notty.I.string Notty.A.empty text)

let render ~width:columns ~label ~hint editor =
  if columns <= 0 then ""
  else
    let text = Text_edit.text editor and cursor = Text_edit.cursor editor in
    let before = clean (String.sub text 0 cursor)
    and after = clean (String.sub text cursor (String.length text - cursor)) in
    let label = clean label and hint = clean hint in
    let complete = label ^ before ^ "▏" ^ after ^ hint in
    if width complete <= columns then complete
    else
      (* Long values take priority over hints so the edit cursor remains visible. *)
      let label = Text_layout.ellipsize (min (width label) (columns / 2)) label in
      label ^ Text_layout.cursor_window (columns - width label) ~before ~after
