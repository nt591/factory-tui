type 'a t = {
  items : 'a list;
  offset : int;
  first : int;
  last : int;
  total : int;
  above : bool;
  below : bool;
}

let make ~capacity ~selected ~scroll items =
  let capacity = max 0 capacity in
  let total = List.length items in
  let maximum = max 0 (total - max 1 capacity) in
  let offset =
    if scroll > 0 then min scroll maximum
    else min maximum (max 0 (selected - capacity + 1))
  in
  let items =
    List.filteri (fun index _ -> index >= offset && index - offset < capacity) items
  in
  let count = List.length items in
  {
    items;
    offset;
    first = (if count = 0 then 0 else offset + 1);
    last = (if count = 0 then 0 else offset + count);
    total;
    above = offset > 0;
    below = offset + count < total;
  }

let cue window =
  if not (window.above || window.below) then ""
  else
    Printf.sprintf "%d-%d/%d%s%s" window.first window.last window.total
      (if window.above then " ↑" else "")
      (if window.below then " ↓" else "")
