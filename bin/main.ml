open Factory_tui

let () =
  let snapshot = ref false
  and size = ref "120x36"
  and events = ref ""
  and database = ref None
  and config = ref None
  and no_config = ref false in
  Arg.parse
    [
      ("--snapshot", Arg.Set snapshot, " Render one non-interactive demo frame");
      ("--size", Arg.Set_string size, "COLSxROWS Snapshot size (default 120x36)");
      ( "--events",
        Arg.Set_string events,
        "PATH Read fixture JSONL from a file or FIFO instead of demo timers" );
      ( "--database",
        Arg.String (fun value -> database := Some value),
        "PATH Persist simulated conversations in an explicit SQLite database" );
      ( "--config",
        Arg.String (fun value -> config := Some value),
        "PATH Load explicit TOML config" );
      ( "--no-config",
        Arg.Set no_config,
        " Ignore default TOML config and use memory unless --database is given" );
    ]
    (fun _ -> raise (Arg.Bad "Unexpected positional argument."))
    "factory-tui [--snapshot] [--events PATH] [--database PATH]";
  try
    if !snapshot then (
      if !database <> None || !events <> "" || !config <> None then
        invalid_arg "Snapshot mode does not open storage or event sources.";
      App.snapshot ~size:!size (Controller.create ()))
    else
      let home = Option.value ~default:(Sys.getcwd ()) (Sys.getenv_opt "HOME") in
      match
        Config.resolve ~home
          ~xdg:(Sys.getenv_opt "XDG_CONFIG_HOME")
          ~config:!config ~no_config:!no_config ~database:!database
      with
      | Error error ->
          prerr_endline error;
          exit 2
      | Ok database -> (
          match
            App.interactive ~events:!events ~database:(Option.value ~default:"" database)
          with
          | Ok () -> ()
          | Error error ->
              prerr_endline error;
              exit 2)
  with
  | Invalid_argument error ->
      prerr_endline error;
      exit 2
  | Unix.Unix_error _ | Sys_error _ ->
      prerr_endline "Cannot open the requested local file.";
      exit 2
