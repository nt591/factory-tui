type t = {
  rows : string list;
  first : int;
  last : int;
  total : int;
  above : bool;
  below : bool;
}

let clean text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code = 10 then Buffer.add_char buffer '\n'
          else if code < 32 || (code >= 127 && code <= 159) then
            Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let make ~width ~capacity ~preview ~editor =
  let width = max 1 width and capacity = max 0 capacity in
  let prompt, before =
    match editor with
    | None -> ("  " ^ clean preview, None)
    | Some editor ->
        let text = Text_edit.text editor and cursor = Text_edit.cursor editor in
        let before = "> " ^ clean (String.sub text 0 cursor) ^ "▏" in
        ( before ^ clean (String.sub text cursor (String.length text - cursor)),
          Some before )
  in
  let rows = Text_layout.wrap width prompt in
  let total = List.length rows in
  let cursor_row =
    match before with
    | None -> total - 1
    | Some before -> List.length (Text_layout.wrap width before) - 1
  in
  let offset = max 0 (cursor_row - max 1 capacity + 1) in
  let visible =
    List.filteri (fun index _ -> index >= offset && index - offset < capacity) rows
  in
  let count = List.length visible in
  {
    rows = visible;
    first = (if count = 0 then 0 else offset + 1);
    last = (if count = 0 then 0 else offset + count);
    total;
    above = count > 0 && offset > 0;
    below = offset + count < total;
  }

let position ~width t =
  if t.first = 0 || not (t.above || t.below) then ""
  else
    Text_layout.ellipsize width
      (Printf.sprintf "draft rows %d-%d/%d%s%s" t.first t.last t.total
         (if t.above then " ↑" else "")
         (if t.below then " ↓" else ""))
