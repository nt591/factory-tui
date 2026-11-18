type action = Search | Reveal_selected
type hit = { x : int; width : int; action : action }
type t = { text : string; hits : hit list }

let width value = Notty.I.width (Notty.I.string Notty.A.empty value)

let base ~width:columns ~archive ~repository ~count ~query =
  let label =
    if archive then "Archive"
    else Option.value ~default:"Session board" repository |> Terminal_text.line
  in
  let count = Printf.sprintf "%d tasks%s" count (if archive then " accepted" else "") in
  let search = if query = "" then "/ search tasks" else "/ " ^ Terminal_text.line query in
  let full = " " ^ label ^ "  |  " ^ count ^ "  | " ^ search in
  let label, search =
    if width full <= columns then (label, search)
    else
      let available = columns - width count - 10 in
      if available >= 12 then
        let label_width = min (width label) (max 4 (available / 2)) in
        ( Text_layout.ellipsize label_width label,
          Text_layout.ellipsize (available - label_width) search )
      else ("", search)
  in
  if label <> "" then
    let prefix = " " ^ label ^ "  |  " ^ count ^ "  | " in
    {
      text = prefix ^ search;
      hits = [ { x = width prefix; width = width search; action = Search } ];
    }
  else
    let prefix = " " ^ count ^ "  | " in
    let available = columns - width prefix in
    if available >= 3 then
      let search = Text_layout.ellipsize available search in
      (* Search remains an explicit control even when the view label cannot fit. *)
      {
        text = prefix ^ search;
        hits = [ { x = width prefix; width = width search; action = Search } ];
      }
    else { text = Text_layout.ellipsize columns (" " ^ count); hits = [] }

let make ~width:columns ~archive ~repository ~count ~query ~hidden =
  let button =
    if (not hidden) || columns < 32 then ""
    else if columns < 70 then "[Show card]"
    else "[Chat off-board / Show card]"
  in
  if button = "" then base ~width:columns ~archive ~repository ~count ~query
  else
    let summary =
      base ~width:(columns - String.length button - 3) ~archive ~repository ~count ~query
    in
    let x = width summary.text + 3 in
    {
      text = summary.text ^ " | " ^ button;
      hits =
        summary.hits @ [ { x; width = String.length button; action = Reveal_selected } ];
    }
