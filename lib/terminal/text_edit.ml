type t = { text : string; cursor : int }

let create text = { text; cursor = String.length text }
let text t = t.text
let cursor t = t.cursor
let continuation char = Char.code char land 0xc0 = 0x80

let previous text offset =
  let rec loop i = if i > 0 && continuation text.[i] then loop (i - 1) else i in
  if offset = 0 then 0 else loop (offset - 1)

let next text offset =
  let rec loop i =
    if i < String.length text && continuation text.[i] then loop (i + 1) else i
  in
  if offset >= String.length text then String.length text else loop (offset + 1)

let insert t value =
  if String.length t.text + String.length value > 65536 then t
  else
    {
      text =
        String.sub t.text 0 t.cursor ^ value
        ^ String.sub t.text t.cursor (String.length t.text - t.cursor);
      cursor = t.cursor + String.length value;
    }

let left t = { t with cursor = previous t.text t.cursor }
let right t = { t with cursor = next t.text t.cursor }

let line_start t =
  let rec loop i = if i = 0 || t.text.[i - 1] = '\n' then i else loop (i - 1) in
  loop t.cursor

let line_end t =
  match String.index_from_opt t.text t.cursor '\n' with
  | Some i -> i
  | None -> String.length t.text

let home t = { t with cursor = line_start t }
let ending t = { t with cursor = line_end t }

let column text start finish =
  let rec loop i count = if i >= finish then count else loop (next text i) (count + 1) in
  loop start 0

let advance text start ending columns =
  let rec loop i n = if i >= ending || n = 0 then i else loop (next text i) (n - 1) in
  loop start columns

let up t =
  let start = line_start t in
  if start = 0 then t
  else
    let ending = start - 1 in
    let previous_start = line_start { t with cursor = ending } in
    {
      t with
      cursor = advance t.text previous_start ending (column t.text start t.cursor);
    }

let down t =
  let ending = line_end t in
  if ending = String.length t.text then t
  else
    let start = ending + 1 in
    let next_end = line_end { t with cursor = start } in
    {
      t with
      cursor = advance t.text start next_end (column t.text (line_start t) t.cursor);
    }

let remove t start finish =
  {
    text =
      String.sub t.text 0 start ^ String.sub t.text finish (String.length t.text - finish);
    cursor = start;
  }

let backspace t = remove t (previous t.text t.cursor) t.cursor
let delete t = remove t t.cursor (next t.text t.cursor)
