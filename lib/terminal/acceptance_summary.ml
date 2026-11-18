type t = { queued : int; draft : bool }

let make ~draft (task : Model.task) =
  {
    queued =
      List.fold_left
        (fun count (message : Model.message) ->
          if message.queued then count + 1 else count)
        0 task.messages;
    draft = String.trim draft <> "";
  }

let pending summary =
  (if summary.queued = 0 then []
   else [ Printf.sprintf "%d queued retained" summary.queued ])
  @ if summary.draft then [ "draft retained" ] else []

let status summary =
  "Task accepted. Chat is read-only. u restores to Ready. No merge, push, or workspace \
   deletion."
  ^
  match pending summary with
  | [] -> ""
  | items -> " " ^ String.concat "; " items ^ "; not sent."

let title ~width summary =
  let prefix = "Accepted / read-only" in
  let text =
    match pending summary with
    | [] -> prefix
    | items -> prefix ^ " · " ^ String.concat " · " items
  in
  Text_layout.ellipsize width text
