type choice = Fetch | Close | Model of string
type hit = { x : int; y : int; width : int; choice : choice }
type t = { rows : string list; footer : string; hits : hit list }

let make picker ~width ~height =
  let inner = max 0 (width - 4) in
  let capacity = max 0 (height - 7) in
  Model_picker.capacity picker capacity;
  let models = Model_picker.visible picker in
  let index = Model_picker.index picker in
  let offset = max 0 (index - capacity + 1) in
  let displayed = List.filteri (fun i _ -> i >= offset && i < offset + capacity) models in
  let items =
    match Model_picker.state picker with
    | Idle -> [ "No request yet. Fetch reads the gateway API key." ]
    | Loading -> [ "Loading... Esc closes; request remains bounded to 12 seconds." ]
    | Error error -> Text_layout.wrap_words (max 1 inner) error
    | Models _ when models = [] ->
        [ "No matching models. Edit the filter or fetch again." ]
    | Models _ ->
        List.mapi
          (fun i model ->
            Text_layout.ellipsize inner
              ((if i + offset = index then "> " else "  ") ^ model))
          displayed
  in
  let items =
    List.init capacity (fun i -> Option.value ~default:"" (List.nth_opt items i))
  in
  let rows =
    [
      "Fetch uses credentials; selecting starts no agent.";
      "Listed IDs are not verified for Codex compatibility.";
      "Filter: " ^ Model_picker.query picker;
    ]
    @ items
    @ [ "Type filters / arrows select / Enter applies / Esc closes" ]
  in
  let footer, controls =
    if width >= 35 && height >= 2 then
      ( "[Fetch / Ctrl-R]  [Close / Esc]",
        [
          { x = 3; y = height - 1; width = 15; choice = Fetch };
          { x = 20; y = height - 1; width = 13; choice = Close };
        ] )
    else if width >= 18 && height >= 2 then
      ("[Close / Esc]", [ { x = 3; y = height - 1; width = 13; choice = Close } ])
    else ("", [])
  in
  let hits =
    match Model_picker.state picker with
    | Models _ when width >= 5 ->
        List.mapi
          (fun i model -> { x = 1; y = 4 + i; width = width - 2; choice = Model model })
          displayed
    | _ -> []
  in
  { rows; footer; hits = controls @ hits }
