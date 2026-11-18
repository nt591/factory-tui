type t = { text : string; cursor : int; boundaries : int array Lazy.t }

let valid_utf8 text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ character ->
      Uutf.Buffer.add_utf_8 buffer
        (match character with `Uchar u -> u | `Malformed _ -> Uutf.u_rep))
    () text;
  Buffer.contents buffer

let boundaries text =
  let _, offsets =
    Uuseg_string.fold_utf_8 `Grapheme_cluster
      (fun (offset, offsets) cluster ->
        let offset = offset + String.length cluster in
        (offset, offset :: offsets))
      (0, [ 0 ]) text
  in
  Array.of_list (List.rev offsets)

let make text cursor = { text; cursor; boundaries = lazy (boundaries text) }

let create text =
  let text = valid_utf8 text in
  make text (String.length text)

let text t = t.text
let cursor t = t.cursor

let lower_bound offsets offset =
  let rec search left right =
    if left >= right then left
    else
      let middle = left + ((right - left) / 2) in
      if offsets.(middle) < offset then search (middle + 1) right else search left middle
  in
  search 0 (Array.length offsets - 1)

let previous t offset =
  let offsets = Lazy.force t.boundaries in
  let index = lower_bound offsets offset in
  offsets.(max 0 (index - 1))

let next t offset =
  let offsets = Lazy.force t.boundaries in
  let index = lower_bound offsets offset in
  offsets.(min (Array.length offsets - 1) (index + 1))

let snap t offset =
  let offsets = Lazy.force t.boundaries in
  { t with cursor = offsets.(lower_bound offsets offset) }

let insert t value =
  let value = valid_utf8 value in
  if value = "" || String.length t.text + String.length value > 65536 then t
  else
    let offset = t.cursor + String.length value in
    let result =
      make
        (String.sub t.text 0 t.cursor ^ value
        ^ String.sub t.text t.cursor (String.length t.text - t.cursor))
        offset
    in
    (* Inserted text can join the following grapheme; the cursor must not split it. *)
    if t.cursor = String.length t.text then result else snap result offset

let left t = { t with cursor = previous t t.cursor }
let right t = { t with cursor = next t t.cursor }

let line_start t =
  let rec loop i = if i = 0 || t.text.[i - 1] = '\n' then i else loop (i - 1) in
  loop t.cursor

let before_newline text offset =
  if offset > 0 && text.[offset - 1] = '\r' then offset - 1 else offset

let line_end t =
  match String.index_from_opt t.text t.cursor '\n' with
  | Some i -> before_newline t.text i
  | None -> String.length t.text

let home t = { t with cursor = line_start t }
let ending t = { t with cursor = line_end t }

let column t start finish =
  let rec loop i count = if i >= finish then count else loop (next t i) (count + 1) in
  loop start 0

let advance t start ending columns =
  let rec loop i n = if i >= ending || n = 0 then i else loop (next t i) (n - 1) in
  loop start columns

let up t =
  let start = line_start t in
  if start = 0 then t
  else
    let ending = before_newline t.text (start - 1) in
    let previous_start = line_start { t with cursor = ending } in
    { t with cursor = advance t previous_start ending (column t start t.cursor) }

let down t =
  match String.index_from_opt t.text t.cursor '\n' with
  | None -> t
  | Some newline ->
      let start = newline + 1 in
      let ending = line_end { t with cursor = start } in
      { t with cursor = advance t start ending (column t (line_start t) t.cursor) }

let remove t start finish =
  if start = finish then t
  else
    let result =
      make
        (String.sub t.text 0 start
        ^ String.sub t.text finish (String.length t.text - finish))
        start
    in
    (* Removing a separator can join clusters on both sides. *)
    snap result start

let backspace t = remove t (previous t t.cursor) t.cursor
let delete t = remove t t.cursor (next t t.cursor)
