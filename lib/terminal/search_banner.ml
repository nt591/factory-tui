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

let text ~width:columns ~query ~editing ~position ~count =
  let query = clean query ^ if editing then "▏" else "" in
  let result = Printf.sprintf "%d/%d messages" position count in
  let full = " /chat " ^ query ^ " · " ^ result ^ " · n/N matches" in
  if width full <= columns then full
  else
    (* Match position and navigation remain visible when the query exceeds the pane. *)
    let prefix = " " ^ result ^ " · n/N · " in
    let prefix =
      if width prefix <= columns then prefix
      else " " ^ Printf.sprintf "%d/%d" position count ^ " · n/N"
    in
    let remaining = columns - width prefix in
    Text_layout.ellipsize columns
      (prefix ^ if remaining > 0 then Text_layout.ellipsize remaining query else "")
