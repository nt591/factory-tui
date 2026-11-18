let width text = Notty.I.width (Notty.I.string Notty.A.empty text)

let text ~width:columns ~query ~editing ~position ~count =
  let query = Terminal_text.line query ^ if editing then "▏" else "" in
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
