open Controller

let text ~width ~input ~focus ~expanded ~searching ~prefix =
  let expansion = if expanded then "e: return" else "e: expand" in
  let hint =
    match input with
    | Compose -> "INSERT / Enter queues · Esc keeps draft · Ctrl-L newline · arrows edit"
    | Edit_model -> "MODEL / Enter applies · Esc cancels · arrows edit · Home/End"
    | New_task -> "NEW TASK / Enter creates · Esc cancels · arrows edit · Home/End"
    | Search -> "BOARD SEARCH / Enter finishes · Esc closes · arrows edit"
    | Chat_search -> "CHAT SEARCH / Enter finishes · Esc clears · arrows edit"
    | Normal -> (
        match prefix with
        | Window -> "PANE / hjkl: focus · w: cycle · +/-: size · =: reset"
        | No_prefix | Go -> (
            match focus with
            | Board when not expanded ->
                "hjkl/arrows: cards · Enter: expand · /: filter · Tab: panes · ?: help"
            | Board | Conversation ->
                if searching then
                  "n/N: matches · Esc: clear search · j/k: scroll · End: latest · Tab: \
                   panes"
                else
                  "j/k: scroll · End: latest · /: search · Tab: panes · " ^ expansion
                  ^ " · ?: help"
            | Activity ->
                "j/k: scroll · t: tools · T: raw · Tab: panes · " ^ expansion
                ^ " · ?: help"))
  in
  Text_layout.ellipsize width (" " ^ hint)
