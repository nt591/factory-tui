type action = Refresh | Edit_executable | Close | Next_file | Previous_file
type hit = { x : int; width : int; action : action }
type t = { text : string; hits : hit list }

(* Labels contain ASCII only, so byte lengths equal terminal cell widths. *)
let length items =
  match items with
  | [] -> 0
  | _ ->
      1
      + List.fold_left (fun total (text, _) -> total + String.length text) 0 items
      + (2 * (List.length items - 1))

let make ~width ~editing ~files =
  let full =
    if editing then [ ("[Close / Esc]", Close) ]
    else
      [
        ("[Refresh / r]", Refresh);
        ("[jj path / i]", Edit_executable);
        ("[Close / Esc]", Close);
      ]
      @
      if files then [ ("[Prev file]", Previous_file); ("[Next file]", Next_file) ] else []
  in
  let compact =
    if editing then [ ("[Close]", Close) ]
    else [ ("[Refresh]", Refresh); ("[jj]", Edit_executable); ("[Close]", Close) ]
  in
  let items =
    if length full <= width then full
    else if length compact <= width then
      compact
      @
      if files && not editing then [ ("[Prev]", Previous_file); ("[Next]", Next_file) ]
      else []
    else if editing then [ ("[Esc]", Close) ]
    else [ ("[Esc]", Close); ("[r]", Refresh); ("[i]", Edit_executable) ]
  in
  let buffer = Buffer.create (max 0 (min width 128)) in
  let rec append x hits = function
    | [] -> { text = Buffer.contents buffer; hits = List.rev hits }
    | (label, action) :: rest ->
        let size = String.length label in
        if x + size > width then { text = Buffer.contents buffer; hits = List.rev hits }
        else (
          Buffer.add_string buffer (if x = 1 then " " else "  ");
          Buffer.add_string buffer label;
          append (x + size + 2) ({ x; width = size; action } :: hits) rest)
  in
  append 1 [] items
