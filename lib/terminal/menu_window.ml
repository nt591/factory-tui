type t = {
  rows : string list;
  scroll : int;
  capacity : int;
  first : int;
  last : int;
  total : int;
  above : bool;
  below : bool;
}

let make ~height ~scroll rows =
  (* Tabs, spacing, borders, and position text must not cover menu content. *)
  let capacity = max 0 (height - 5) in
  let total = List.length rows in
  let scroll = max 0 (min scroll (max 0 (total - max 1 capacity))) in
  let visible =
    List.filteri (fun index _ -> index >= scroll && index - scroll < capacity) rows
  in
  let count = List.length visible in
  {
    rows = visible;
    scroll;
    capacity;
    first = (if count = 0 then 0 else scroll + 1);
    last = (if count = 0 then 0 else scroll + count);
    total;
    above = scroll > 0;
    below = scroll + count < total;
  }

let position t =
  Printf.sprintf "%d-%d/%d · %s · j/k scroll · Esc closes" t.first t.last t.total
    (match (t.above, t.below) with
    | false, true -> "more below ↓"
    | true, true -> "↑ more ↓"
    | true, false -> "↑ more above"
    | false, false -> "all shown")
