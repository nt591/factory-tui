open Notty

let width text = I.width (I.string A.empty text)

let wrap columns text =
  let columns = max 1 columns in
  let current = Buffer.create (min columns 4096) in
  let cells = ref 0 and rows = ref [] in
  let flush () =
    rows := Buffer.contents current :: !rows;
    Buffer.clear current;
    cells := 0
  in
  Uuseg_string.fold_utf_8 `Grapheme_cluster
    (fun () cluster ->
      if cluster = "\n" then flush ()
      else
        let size = width cluster in
        if !cells + size > columns && !cells > 0 then flush ();
        (* An over-wide grapheme stays whole. The pane crops its display image. *)
        Buffer.add_string current cluster;
        cells := !cells + size)
    () text;
  flush ();
  List.rev !rows

let wrap_words columns text =
  let columns = max 1 columns in
  let words = String.split_on_char ' ' text in
  let rec loop current rows = function
    | [] -> List.rev (if current = "" then rows else current :: rows)
    | word :: rest -> (
        let combined = if current = "" then word else current ^ " " ^ word in
        if width combined <= columns then loop combined rows rest
        else if current <> "" then loop "" (current :: rows) (word :: rest)
        else
          let parts = wrap columns word in
          match List.rev parts with
          | last :: previous -> loop last (previous @ rows) rest
          | [] -> loop "" rows rest)
  in
  loop "" [] words

let ellipsize ?(more = false) columns text =
  if columns <= 0 then ""
  else if (not more) && width text <= columns then text
  else
    let marker = "…" in
    let remaining = columns - width marker in
    let prefix = Buffer.create (min columns 4096) in
    let used = ref 0 and finished = ref false in
    Uuseg_string.fold_utf_8 `Grapheme_cluster
      (fun () cluster ->
        if not !finished then
          let size = width cluster in
          if !used + size > remaining then finished := true
          else (
            Buffer.add_string prefix cluster;
            used := !used + size))
      () text;
    Buffer.contents prefix ^ marker

let limit_rows ~width ~height rows =
  let rec select remaining = function
    | _ when remaining <= 0 -> []
    | [] -> []
    | row :: rest when remaining = 1 -> [ ellipsize ~more:(rest <> []) width row ]
    | row :: rest -> ellipsize width row :: select (remaining - 1) rest
  in
  select height rows

let cursor_window columns ~before ~after =
  if columns <= 0 then ""
  else
    let marker = "▏" in
    let available = max 0 (columns - width marker) in
    let clusters text =
      Uuseg_string.fold_utf_8 `Grapheme_cluster
        (fun rows cluster -> cluster :: rows)
        [] text
    in
    let rec take remaining selected = function
      | [] -> (selected, remaining)
      | cluster :: rest ->
          let size = width cluster in
          if size > remaining then (selected, remaining)
          else take (remaining - size) (cluster :: selected) rest
    in
    (* Forward context must remain visible while editing inside a long value. *)
    let forward = min (width after) (available / 3) in
    let left, remaining = take (available - forward) [] (clusters before) in
    let right, _ = take (remaining + forward) [] (List.rev (clusters after)) in
    String.concat "" left ^ marker ^ String.concat "" (List.rev right)
