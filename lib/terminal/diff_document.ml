type file = { index : int; line : int; name : string }
type t = { lines : string array; files : file array }

let suffix prefix text =
  if String.starts_with ~prefix text then
    Some
      (String.sub text (String.length prefix) (String.length text - String.length prefix))
  else None

let path prefix text =
  match suffix prefix text with
  | None | Some "/dev/null" -> None
  | Some value -> (
      match suffix "a/" value with
      | Some value -> Some value
      | None -> Some (Option.value ~default:value (suffix "b/" value)))

let parse patch =
  let lines =
    if patch = "" then [||] else Array.of_list (String.split_on_char '\n' patch)
  in
  let headers = ref [] in
  Array.iteri
    (fun line text ->
      if String.starts_with ~prefix:"diff --git " text then headers := line :: !headers)
    lines;
  let headers = Array.of_list (List.rev !headers) in
  let files =
    Array.mapi
      (fun index line ->
        let stop =
          if index + 1 < Array.length headers then headers.(index + 1)
          else Array.length lines
        in
        let rec name row deleted =
          if row >= stop || String.starts_with ~prefix:"@@" lines.(row) then deleted
          else
            match path "+++ " lines.(row) with
            | Some value -> Some value
            | None -> (
                match suffix "rename to " lines.(row) with
                | Some value -> Some value
                | None ->
                    name (row + 1)
                      (match path "--- " lines.(row) with
                      | Some value -> Some value
                      | None -> deleted))
        in
        (* Quoted paths remain opaque. File labels never become command arguments. *)
        let name =
          Option.value
            ~default:(Option.get (suffix "diff --git " lines.(line)))
            (name (line + 1) None)
        in
        { index; line; name })
      headers
  in
  { lines; files }

let line_count t = Array.length t.lines
let file_count t = Array.length t.files
let fold_lines t ~init ~f = Array.fold_left f init t.lines

let lines t ~start ~count =
  let start = max 0 (min (Array.length t.lines) start) in
  let count = max 0 (min (Array.length t.lines - start) count) in
  List.init count (fun offset -> t.lines.(start + offset))

let file_index t line =
  let rec search low high =
    if low >= high then low - 1
    else
      let middle = low + ((high - low) / 2) in
      if t.files.(middle).line <= line then search (middle + 1) high
      else search low middle
  in
  search 0 (Array.length t.files)

let file_at t ~line =
  let index = file_index t line in
  if index < 0 then None else Some t.files.(index)

let next_file t ~line =
  let index = file_index t line + 1 in
  if index >= Array.length t.files then None else Some t.files.(index)

let previous_file t ~line =
  let index = file_index t line in
  if index <= 0 then None else Some t.files.(index - 1)
