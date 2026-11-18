let describe (saved : Snapshot.t) =
  let interrupted =
    List.fold_left
      (fun count (task : Model.task) ->
        if task.state = Model.Working then count + 1 else count)
      0 saved.tasks
  in
  let drafts =
    List.fold_left
      (fun count (_, text) -> if text = "" then count else count + 1)
      0 saved.drafts
  in
  let recovery =
    if interrupted = 0 then " No interrupted runs."
    else
      Printf.sprintf " %d interrupted %s; no agent resumed." interrupted
        (if interrupted = 1 then "run" else "runs")
  in
  let draft =
    if drafts = 0 then ""
    else
      Printf.sprintf " %d saved %s retained." drafts
        (if drafts = 1 then "draft" else "drafts")
  in
  "Saved conversations restored." ^ recovery ^ draft
