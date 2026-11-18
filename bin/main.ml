open Factory_tui

let () =
  let snapshot = ref false
  and size = ref "120x36"
  and events = ref ""
  and database = ref None
  and config = ref None
  and no_config = ref false
  and fake_harness = ref false
  and list_models = ref false
  and check_config = ref None
  and check_gateway = ref None
  and dry_run = ref false
  and run_codex = ref false
  and live_ui = ref false
  and demo = ref false
  and workspace_write = ref false
  and reasoning = ref None
  and executable = ref None
  and directory = ref None
  and model = ref None
  and thread_id = ref None
  and gateway_file = ref None in
  Arg.parse
    [
      ( "--reasoning-effort",
        Arg.String (fun value -> reasoning := Some value),
        "EFFORT Request low, medium or high reasoning for live UI runs" );
      ( "--workspace-write",
        Arg.Set workspace_write,
        " Explicit write access for real runs" );
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "factory-tui 0.1.0";
            exit 0),
        " Print version without reading config or starting anything" );
      ("--demo", Arg.Set demo, " Open simulated tasks explicitly; no model calls");
      ( "--live-ui",
        Arg.Set live_ui,
        " Compatibility flag: real UI is the default; SQLite required" );
      ( "--run-codex",
        Arg.Set run_codex,
        " Execute a read-only agent explicitly; stdin prompt and --database required" );
      ( "--dry-run-codex",
        Arg.Set dry_run,
        " Show invocation JSON; no process, database, or credentials" );
      ( "--codex-executable",
        Arg.String (fun value -> executable := Some value),
        "PATH Absolute Codex executable for explicit execution or preview" );
      ( "--workspace",
        Arg.String (fun value -> directory := Some value),
        "PATH Existing absolute workspace for headless execution or preview" );
      ( "--model",
        Arg.String (fun value -> model := Some value),
        "ID Model for headless execution or preview" );
      ( "--resume",
        Arg.String (fun value -> thread_id := Some value),
        "ID Explicit thread for headless resume or preview" );
      ( "--list-models",
        Arg.Set list_models,
        " Fetch gateway model IDs explicitly; reads referenced API key, no agent" );
      ( "--gateway",
        Arg.String (fun value -> gateway_file := Some value),
        "PATH Non-secret gateway config for explicit execution or preview" );
      ( "--check-config",
        Arg.String (fun path -> check_config := Some path),
        "PATH Validate TOML and print resolved settings; no database or process" );
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
        "PATH Persist conversations in an explicit SQLite database" );
      ( "--config",
        Arg.String (fun value -> config := Some value),
        "PATH Load explicit TOML config" );
      ( "--no-config",
        Arg.Set no_config,
        " Ignore default TOML config and use memory unless --database is given" );
    ]
    (fun _ -> raise (Arg.Bad "Unexpected positional argument."))
    "factory-tui [--config PATH | --no-config] [--database PATH]\n\
     See --help for snapshot, fixture, preview, and explicit live execution modes.";
  let default_live =
    not
      (!demo || !live_ui || !run_codex || !dry_run || !snapshot || !fake_harness
     || !events <> "" || !list_models || !check_config <> None || !check_gateway <> None)
  in
  if default_live then live_ui := true;
  try
    if
      !demo
      && (!live_ui || !run_codex || !dry_run || !snapshot || !fake_harness
        || !events <> "" || !list_models || !check_config <> None
        || !check_gateway <> None)
    then invalid_arg "--demo cannot be combined with other execution or check modes.";
    let reasoning =
      match !reasoning with
      | None -> None
      | Some value -> (
          if not !live_ui then invalid_arg "--reasoning-effort requires --live-ui.";
          match Reasoning_effort.parse value with
          | Ok effort -> Some effort
          | Error error -> invalid_arg error)
    in
    if !list_models then (
      if
        !workspace_write || !live_ui || !run_codex || !dry_run || !snapshot
        || !events <> "" || !database <> None || !config <> None || !no_config
        || !fake_harness || !check_gateway <> None || !check_config <> None
        || !directory <> None || !model <> None || !thread_id <> None
        || !executable <> None
      then
        invalid_arg
          "Model discovery cannot be combined with execution, storage or other check \
           modes.";
      let file =
        match !gateway_file with
        | Some file -> file
        | None -> invalid_arg "Model discovery requires --gateway PATH."
      in
      let result =
        Result.bind (Gateway.load file)
          (Gateway_models.fetch ~curl:"/usr/bin/curl" ~lookup:Sys.getenv_opt)
      in
      match result with
      | Error error ->
          prerr_endline error;
          exit 2
      | Ok models ->
          print_endline
            (Yojson.Basic.pretty_to_string
               (`Assoc
                  [
                    ("models", `List (List.map (fun id -> `String id) models));
                    ("starts_agent", `Bool false);
                    ("compatibility_verified", `Bool false);
                  ]));
          exit 0);
    if !check_config <> None then (
      if
        !workspace_write || !live_ui || !run_codex || !dry_run || !snapshot
        || !events <> "" || !config <> None || !no_config || !fake_harness
        || !check_gateway <> None || !directory <> None || !model <> None
        || !thread_id <> None || !gateway_file <> None || !executable <> None
      then
        invalid_arg
          "Config checks cannot be combined with execution or other check modes.";
      let home = Option.value ~default:(Sys.getcwd ()) (Sys.getenv_opt "HOME") in
      match
        Config.resolve_settings ~home ~xdg:None ~config:!check_config ~no_config:false
          ~database:!database
      with
      | Error error ->
          prerr_endline error;
          exit 2
      | Ok settings ->
          print_endline (Yojson.Basic.pretty_to_string (Config_preview.describe settings));
          exit 0);
    if !workspace_write && not !live_ui then
      invalid_arg
        "--workspace-write requires --live-ui; headless execution stays read-only.";
    if !run_codex then (
      if
        !live_ui || !dry_run || !snapshot || !events <> "" || !config <> None
        || !fake_harness || !check_gateway <> None
      then
        invalid_arg
          "Live execution cannot be combined with other execution modes or default \
           config.";
      let required name = function
        | Some value -> value
        | None -> invalid_arg ("Run requires " ^ name ^ ".")
      in
      let executable = required "--codex-executable" !executable
      and directory = required "--workspace" !directory
      and model = required "--model" !model
      and database = required "--database" !database in
      let buffer = Bytes.create 65537 in
      let rec read offset =
        if offset = Bytes.length buffer then offset
        else
          let count = input stdin buffer offset (Bytes.length buffer - offset) in
          if count = 0 then offset else read (offset + count)
      in
      let count = read 0 in
      if count > 65536 then invalid_arg "Run prompt exceeds 64 KiB.";
      let cancelled = ref false in
      let signals =
        List.map
          (fun signal ->
            (signal, Sys.signal signal (Sys.Signal_handle (fun _ -> cancelled := true))))
          [ Sys.sigint; Sys.sigterm ]
      in
      let result =
        Fun.protect
          ~finally:(fun () ->
            List.iter (fun (signal, handler) -> Sys.set_signal signal handler) signals)
          (fun () ->
            Execution.run ~executable ~directory ~model ~thread_id:!thread_id
              ~gateway_file:!gateway_file ~database
              ~prompt:(Bytes.sub_string buffer 0 count) ~cancelled:(fun () -> !cancelled))
      in
      match result with
      | Error error ->
          prerr_endline error;
          exit 2
      | Ok summary ->
          print_endline
            (Yojson.Basic.to_string
               (`Assoc
                  [
                    ("task_id", `String summary.task_id);
                    ("state", `String (Model.label summary.state));
                    ("succeeded", `Bool summary.succeeded);
                    ( "thread_id",
                      match summary.thread_id with None -> `Null | Some id -> `String id
                    );
                  ]));
          if not summary.succeeded then exit 1)
    else if !live_ui then (
      if
        !snapshot || !events <> "" || !fake_harness || !check_gateway <> None || !dry_run
        || !directory <> None || !model <> None || !thread_id <> None
      then
        invalid_arg
          "Live UI cannot be combined with other execution modes or per-run arguments.";
      let home = Option.value ~default:(Sys.getcwd ()) (Sys.getenv_opt "HOME") in
      let settings =
        match
          Config.resolve_settings ~home
            ~xdg:(Sys.getenv_opt "XDG_CONFIG_HOME")
            ~config:!config ~no_config:!no_config ~database:!database
        with
        | Ok ({ database = Some _; _ } as settings) -> settings
        | Ok _ ->
            invalid_arg
              "No real-board storage configured. Run ./scripts/setup.sh, or use --demo."
        | Error error -> invalid_arg error
      in
      let executable =
        match (!executable, settings.codex.executable) with
        | Some path, _ | None, Some path -> path
        | None, None -> (
            match Executable_path.resolve "codex" with
            | Some path -> path
            | None ->
                invalid_arg
                  "Codex was not found on PATH. Install it or set codex.executable.")
      in
      let gateway_file =
        match !gateway_file with
        | Some _ as value -> value
        | None -> settings.codex.gateway_file
      in
      let reasoning =
        match reasoning with Some _ as value -> value | None -> settings.codex.reasoning
      in
      let live =
        match Live_runner.configure ~executable ~gateway_file with
        | Ok config ->
            let config =
              Option.fold ~none:config ~some:(Live_runner.with_reasoning config) reasoning
            in
            Live_runner.with_policy config
              (if !workspace_write then Model.Workspace_write else Model.Read_only)
        | Error error -> invalid_arg error
      in
      match
        App.interactive ~allow_demo_history:(not default_live) ~projects:settings.projects
          ~live ~workspace_defaults:settings.workspace ~layout:settings.layout ~events:""
          ~database:(Option.get settings.database)
          ()
      with
      | Ok () -> ()
      | Error error ->
          prerr_endline error;
          exit 2)
    else if !dry_run then (
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
      then
        invalid_arg
          "Codex invocation options require --dry-run-codex, --run-codex, or --live-ui.";
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
          Config.resolve_settings ~home
            ~xdg:(Sys.getenv_opt "XDG_CONFIG_HOME")
            ~config:!config ~no_config:!no_config ~database:!database
        with
        | Error error ->
            prerr_endline error;
            exit 2
        | Ok settings -> (
            match
              App.interactive ~projects:settings.projects ~fake_harness:!fake_harness
                ~events:!events ~workspace_defaults:settings.workspace
                ~layout:settings.layout
                ~database:(Option.value ~default:"" settings.database)
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
