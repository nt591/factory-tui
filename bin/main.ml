open Factory_tui

let () =
  let snapshot = ref false
  and size = ref "120x36"
  and events = ref ""
  and database = ref None
  and config = ref None
  and no_config = ref false
  and fake_harness = ref false
  and check_gateway = ref None
  and dry_run = ref false
  and executable = ref None
  and directory = ref None
  and model = ref None
  and thread_id = ref None
  and gateway_file = ref None in
  Arg.parse
    [
      ( "--dry-run-codex",
        Arg.Set dry_run,
        " Show invocation JSON; no process, database, or credentials" );
      ( "--codex-executable",
        Arg.String (fun value -> executable := Some value),
        "PATH Absolute Codex executable for dry-run" );
      ( "--workspace",
        Arg.String (fun value -> directory := Some value),
        "PATH Existing absolute workspace for dry-run" );
      ("--model", Arg.String (fun value -> model := Some value), "ID Model for dry-run");
      ( "--resume",
        Arg.String (fun value -> thread_id := Some value),
        "ID Explicit thread for dry-run" );
      ( "--gateway",
        Arg.String (fun value -> gateway_file := Some value),
        "PATH Non-secret gateway config for dry-run" );
      ( "--check-gateway",
        Arg.String (fun path -> check_gateway := Some path),
        "PATH Validate non-secret gateway config without network or credentials" );
      ( "--fake-harness",
        Arg.Set fake_harness,
        " Use local process fixtures; s starts one explicitly" );
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
    if !dry_run then (
      if
        !snapshot || !database <> None || !events <> "" || !config <> None
        || !fake_harness || !check_gateway <> None
      then
        invalid_arg
          "Dry-run cannot be combined with interactive, storage, or other check modes.";
      let required name = function
        | Some value -> value
        | None -> invalid_arg ("Dry-run requires " ^ name ^ ".")
      in
      match
        Invocation_preview.build
          ~executable:(required "--codex-executable" !executable)
          ~directory:(required "--workspace" !directory)
          ~model:(required "--model" !model) ~thread_id:!thread_id
          ~gateway_file:!gateway_file
      with
      | Ok json -> print_endline (Yojson.Basic.pretty_to_string json)
      | Error error ->
          prerr_endline error;
          exit 2)
    else (
      if
        !directory <> None || !model <> None || !thread_id <> None
        || !gateway_file <> None || !executable <> None
      then invalid_arg "Codex invocation options require --dry-run-codex.";
      if !check_gateway <> None then (
        if
          !snapshot || !database <> None || !events <> "" || !config <> None
          || !fake_harness
        then
          invalid_arg
            "Gateway checks cannot be combined with interactive or snapshot options.";
        match Gateway.load (Option.get !check_gateway) with
        | Ok _ ->
            print_endline
              "Gateway config is valid. No credentials read; network compatibility is \
               unverified."
        | Error error ->
            prerr_endline error;
            exit 2)
      else if !snapshot then (
        if !database <> None || !events <> "" || !config <> None || !fake_harness then
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
              App.interactive ~fake_harness:!fake_harness ~events:!events
                ~database:(Option.value ~default:"" database)
                ()
            with
            | Ok () -> ()
            | Error error ->
                prerr_endline error;
                exit 2))
  with
  | Invalid_argument error ->
      prerr_endline error;
      exit 2
  | Unix.Unix_error _ | Sys_error _ ->
      prerr_endline "Cannot open the requested local file.";
      exit 2
