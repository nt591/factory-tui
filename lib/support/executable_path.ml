let find ~path name =
  if name = "" || String.contains name '/' || String.contains name '\000' then None
  else
    String.split_on_char ':' path
    |> List.find_map (fun directory ->
        let directory = if directory = "" then Sys.getcwd () else directory in
        let candidate = Filename.concat directory name in
        try
          Unix.access candidate [ Unix.X_OK ];
          if (Unix.stat candidate).Unix.st_kind = Unix.S_REG then
            Some
              (if Filename.is_relative candidate then
                 Filename.concat (Sys.getcwd ()) candidate
               else candidate)
          else None
        with Unix.Unix_error _ -> None)

let resolve name = find ~path:(Option.value ~default:"" (Sys.getenv_opt "PATH")) name
