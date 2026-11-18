type t = {
  mutable task_id : string option;
  mutable anchor : (string * int) option;
  mutable distance : int;
  mutable offset : int;
}

type view = { offset : int; distance : int; following : bool }

let create () = { task_id = None; anchor = None; distance = 0; offset = 0 }
let distance (t : t) = t.distance

let reset t =
  t.task_id <- None;
  t.anchor <- None;
  t.distance <- 0;
  t.offset <- 0

let index_of rows id =
  let rec loop i = function
    | [] -> None
    | (row_id, _) :: _ when row_id = id -> Some i
    | _ :: rest -> loop (i + 1) rest
  in
  loop 0 rows

let anchor_index rows (id, line) =
  let rec loop i last = function
    | [] -> last
    | (row_id, row_line) :: rest -> (
        if row_id <> id then loop (i + 1) last rest
        else if row_line = line then Some i
        else if row_line < line then loop (i + 1) (Some i) rest
        else match last with None -> Some i | Some _ -> last)
  in
  loop 0 None rows

let update t ~task_id ~rows ~height ~distance ~seek =
  let height = max 0 height in
  let maximum = max 0 (List.length rows - height) in
  let distance = max 0 distance in
  let same_task = t.task_id = Some task_id in
  let user_moved = (not same_task) || distance <> t.distance in
  let offset =
    match seek with
    | Some id -> Option.value ~default:t.offset (index_of rows id)
    | None when user_moved || distance = 0 -> max 0 (maximum - distance)
    | None -> (
        match t.anchor with
        | Some anchor -> Option.value ~default:t.offset (anchor_index rows anchor)
        | None -> t.offset)
  in
  let offset = max 0 (min maximum offset) in
  let distance = maximum - offset in
  (* A hidden pane must not replace a readable message anchor with empty geometry. *)
  if height > 0 then (
    t.task_id <- Some task_id;
    t.anchor <- List.nth_opt rows offset;
    t.distance <- distance;
    t.offset <- offset);
  { offset; distance; following = distance = 0 }
