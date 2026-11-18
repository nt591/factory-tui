let clean text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code = 10 then Buffer.add_char buffer '\n'
          else if code < 32 || (code >= 127 && code <= 159) then
            Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let rows ~width state =
  let messages =
    match state with
    | Changes.Idle -> [ "Press r / Enter to read the workspace diff. No agent starts." ]
    | Changes.Loading -> [ "Reading workspace changes… input remains responsive." ]
    | Changes.Error error ->
        [
          "Changes error: " ^ error;
          "Retain the workspace. i edits jj path; r retries explicitly.";
        ]
    | Changes.Patch "" -> [ "No changes relative to this task's recorded base." ]
    | Changes.Patch _ -> []
  in
  List.concat_map
    (fun text ->
      String.split_on_char '\n' (clean text)
      |> List.concat_map (fun line ->
          if line = "" then [ "" ] else Text_layout.wrap_words (max 1 width) line))
    messages
