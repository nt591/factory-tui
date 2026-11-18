type action = Toggle_archive | Search
type hit = { x : int; width : int; action : action }
type t = { text : string; hits : hit list }

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

let width value = Notty.I.width (Notty.I.string Notty.A.empty value)

let make ~width:columns ~archive ~repository ~count ~query =
  let label =
    if archive then "Archive"
    else Option.value ~default:"Session board" repository |> clean
  in
  let count = Printf.sprintf "%d tasks%s" count (if archive then " accepted" else "") in
  let search = if query = "" then "/ search tasks" else "/ " ^ clean query in
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
      hits =
        [
          { x = 1; width = width label; action = Toggle_archive };
          { x = width prefix; width = width search; action = Search };
        ];
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
