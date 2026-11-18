let duration seconds =
  let seconds = Float.floor seconds in
  if seconds < 60. then Printf.sprintf "%.0fs" seconds
  else if seconds < 3600. then
    Printf.sprintf "%.0fm %.0fs" (Float.floor (seconds /. 60.)) (Float.rem seconds 60.)
  else
    Printf.sprintf "%.0fh %.0fm"
      (Float.floor (seconds /. 3600.))
      (Float.floor (Float.rem seconds 3600. /. 60.))

let describe ~now (record : Model.run_record) =
  let finish =
    match record.ended_at with
    | Some finish -> Some ("recorded duration", finish)
    | None when record.status = Model.Running -> Some ("run age", now)
    | None -> None
  in
  match finish with
  | Some (label, finish)
    when Float.is_finite record.started_at
         && Float.is_finite finish && record.started_at >= 0.
         && finish >= record.started_at
         && Float.is_finite (finish -. record.started_at) ->
      label ^ " " ^ duration (finish -. record.started_at)
  (* Persisted wall-clock timestamps can move backwards or lack a recorded end. *)
  | _ -> "time unavailable"
