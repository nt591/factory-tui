type action = Submit | Close | Newline
type item = { label : string; action : action }

let items = function
  | Controller.Normal -> []
  | Compose ->
      [
        { label = "[Send reply / Enter]"; action = Submit };
        { label = "[Board / Esc]"; action = Close };
        { label = "[Newline / Ctrl-L]"; action = Newline };
      ]
  | Edit_model ->
      [
        { label = "[Apply model / Enter]"; action = Submit };
        { label = "[Cancel / Esc]"; action = Close };
      ]
  | New_task ->
      [
        { label = "[Create task / Enter]"; action = Submit };
        { label = "[Cancel / Esc]"; action = Close };
      ]
  | Search ->
      [
        { label = "[Finish search / Enter]"; action = Submit };
        { label = "[Close / Esc]"; action = Close };
      ]
  | Chat_search ->
      [
        { label = "[Finish search / Enter]"; action = Submit };
        { label = "[Clear search / Esc]"; action = Close };
      ]

let key ~input action =
  match (input, action) with
  | Controller.Normal, _ -> None
  | _, Submit -> Some (`Enter, [])
  | _, Close -> Some (`Escape, [])
  | Compose, Newline -> Some (`ASCII 'l', [ `Ctrl ])
  | _, Newline -> None
