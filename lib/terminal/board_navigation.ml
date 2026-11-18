let index_of selected tasks =
  let rec loop index = function
    | [] -> None
    | (task : Model.task) :: _ when task.id = selected -> Some index
    | _ :: rest -> loop (index + 1) rest
  in
  loop 0 tasks

let vertical ~columns ~selected tasks =
  if not columns then tasks
  else
    match List.find_opt (fun (task : Model.task) -> task.id = selected) tasks with
    | Some task ->
        List.filter
          (fun (candidate : Model.task) ->
            Board_lanes.of_state candidate.state = Board_lanes.of_state task.state)
          tasks
    | None ->
        List.concat_map
          (fun state ->
            List.filter (fun (task : Model.task) -> Board_lanes.contains state task) tasks)
          Board_lanes.states

let move ~selected ~delta tasks =
  let length = List.length tasks in
  if length = 0 then None
  else
    let index =
      Option.value ~default:(if delta >= 0 then -1 else length) (index_of selected tasks)
    in
    let delta = max (-length) (min length delta) in
    Option.map
      (fun (task : Model.task) -> task.id)
      (List.nth_opt tasks (max 0 (min (length - 1) (index + delta))))

let horizontal ~right ~selected tasks =
  match List.find_opt (fun (task : Model.task) -> task.id = selected) tasks with
  | None -> None
  | Some task ->
      let source =
        List.filter
          (fun (candidate : Model.task) ->
            Board_lanes.of_state candidate.state = Board_lanes.of_state task.state)
          tasks
      in
      let row = Option.value ~default:0 (index_of selected source) in
      let states = if right then Board_lanes.states else List.rev Board_lanes.states in
      let rec find = function
        | [] -> None
        | state :: rest when state = Board_lanes.of_state task.state -> next rest
        | _ :: rest -> find rest
      and next = function
        | [] -> None
        | state :: rest -> (
            let candidates =
              List.filter
                (fun (candidate : Model.task) -> Board_lanes.contains state candidate)
                tasks
            in
            match
              List.nth_opt candidates (max 0 (min row (List.length candidates - 1)))
            with
            | Some task -> Some task.id
            | None -> next rest)
      in
      find states

let edge ~last tasks =
  match if last then List.rev tasks else tasks with
  | (task : Model.task) :: _ -> Some task.id
  | [] -> None
