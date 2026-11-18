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
      String.split_on_char '\n' (Terminal_text.multiline text)
      |> List.concat_map (fun line ->
          if line = "" then [ "" ] else Text_layout.wrap_words (max 1 width) line))
    messages
