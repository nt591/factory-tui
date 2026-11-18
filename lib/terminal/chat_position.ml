type t = { text : string; latest : (int * int) option }

let make ~width ~height ~total (view : Chat_viewport.view) =
  if width <= 0 || height <= 0 || total <= height then { text = ""; latest = None }
  else
    let first = min total (view.offset + 1) in
    let last = min total (view.offset + height) in
    let range = Printf.sprintf "rows %d-%d/%d" first last total in
    if view.following then
      { text = Text_layout.ellipsize width (range ^ " · ↑ history"); latest = None }
    else
      let button = "[Latest / End]" in
      if width < String.length button then
        { text = Text_layout.ellipsize width range; latest = None }
      else
        let remaining = width - String.length button in
        let suffix =
          if remaining <= 3 then ""
          else " · " ^ Text_layout.ellipsize (remaining - 3) (range ^ " ↓")
        in
        { text = button ^ suffix; latest = Some (0, String.length button) }
