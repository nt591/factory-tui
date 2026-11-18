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
