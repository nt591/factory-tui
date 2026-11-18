type t = { lines : string array; widest : int }

let create document =
  let widest = ref 0 in
  let lines =
    Diff_document.fold_lines document ~init:[] ~f:(fun lines text ->
        let text = Terminal_text.line text in
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
