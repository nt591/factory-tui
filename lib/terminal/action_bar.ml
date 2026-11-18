open Model
open Controller

let items ~archive ~task ~live ~replay ~fake ~storage ~expanded =
  [ ("Ctrl-P commands", Open_commands) ]
  @ (if archive then [ ("b session board", Session_board) ] else [])
  @ (match task with
    | None -> []
    | Some task ->
        (if task.state = Ready then [ ("Ctrl-A accept & archive", Accept) ] else [])
        @ (if task.workspace <> None then [ ("v changes", Open_review) ] else [])
        @ [
            ( (if expanded then "Esc back" else "e expand"),
              if expanded then Back else Zoom );
          ]
        @ (if task.state = Done then [ ("u restore", Restore_task) ] else [])
        @ (if task.state = Working && not replay then [ ("x stop", Stop) ] else [])
        @ (if task.state <> Done then [ ("i reply", Begin_compose) ] else [])
        @ (if
             task.state <> Working && task.state <> Done && (not replay)
             && List.exists (fun (message : message) -> message.queued) task.messages
             && ((not live)
                || (task.workspace <> None || task.session_root <> None)
                   && task.harness = Codex)
           then [ ((if live then "s send" else "s start"), Start) ]
           else [])
        @
        if task.state = Done then []
        else
          [ ("m model", Begin_model) ]
          @ (if live then [ ("M models", Open_models) ] else [])
          @ if live then [] else [ ("H harness", Next_harness) ])
  @ (if storage then [ ("W workspace", Begin_workspace) ] else [])
  @ (if live then if storage then [ ("n task", Begin_new) ] else []
     else [ ("n demo", Begin_new) ])
  @ (if live || replay || fake then [] else [ ("f pause", Toggle_pause) ])
  @ (if task <> None then [ ("Ctrl-X delete", Begin_delete) ] else [])
  @ [ ("q quit", Quit) ]
