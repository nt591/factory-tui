type t = { lines : string array; widest : int }

let clean text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code < 32 || (code >= 127 && code <= 159) then Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let create document =
  let widest = ref 0 in
  let lines =
    Diff_document.fold_lines document ~init:[] ~f:(fun lines text ->
        let text = clean text in
        widest := max !widest (Notty.I.width (Notty.I.string Notty.A.empty text));
        text :: lines)
    |> List.rev |> Array.of_list
  in
  (* Width is independent of pane geometry. Resize does not require a patch scan. *)
  { lines; widest = !widest }

let widest t = t.widest

let lines t ~start ~count =
  let start = max 0 (min (Array.length t.lines) start) in
  let count = max 0 (min (Array.length t.lines - start) count) in
  List.init count (fun offset -> t.lines.(start + offset))
