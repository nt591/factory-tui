open Scope

type codex = {
  executable : string option;
  gateway_file : string option;
  reasoning : Reasoning_effort.t option;
}

type t = {
  database : string option;
  projects : Project.t list;
  codex : codex;
  workspace : Workspace_defaults.t;
  layout : Pane_layout.defaults;
}

let empty =
  {
    database = None;
    projects = [];
    codex = { executable = None; gateway_file = None; reasoning = None };
    workspace = Workspace_defaults.empty;
    layout = Pane_layout.automatic;
  }

exception Invalid of string

let path ~base ~home value =
  if value = "" || String.exists (fun c -> Char.code c < 32 || Char.code c = 127) value
  then raise (Invalid "Configured path must not be empty or contain controls.");
  let value =
    if value = "~" then home
    else if String.starts_with ~prefix:"~/" value then
      Filename.concat home (String.sub value 2 (String.length value - 2))
    else value
  in
  if Filename.is_relative value then Filename.concat base value else value

let parse ~base ~home source =
  if String.length source > 65536 then Error "Config exceeds 64 KiB."
  else
    try
      let table =
        match Toml.Parser.from_string source with
        | `Ok table -> table
        | `Error _ ->
            raise (Invalid "Invalid TOML config. Source content was not printed.")
      in
      let open Toml.Types in
      let check_keys allowed table =
        Table.iter
          (fun key _ ->
            if not (List.mem (Table.Key.to_string key) allowed) then
              raise
                (Invalid
                   "Unknown config field in storage, workspace, layout or codex settings."))
          table
      in
      let get name table = Table.find_opt (Table.Key.of_string name) table in
      check_keys [ "storage"; "workspace"; "layout"; "codex"; "projects" ] table;
      let database =
        match get "storage" table with
        | None -> None
        | Some (TTable storage) -> (
            check_keys [ "database" ] storage;
            match get "database" storage with
            | None -> None
            | Some (TString value) -> Some (path ~base ~home value)
            | Some _ -> raise (Invalid "storage.database must be a string."))
        | Some _ -> raise (Invalid "storage must be a TOML table.")
      in
      let projects =
        match get "projects" table with
        | None -> []
        | Some (TTable projects) ->
            if Table.cardinal projects > 100 then
              raise (Invalid "Project catalogue is limited to 100 entries.");
            Table.fold
              (fun name value entries ->
                match value with
                | TTable project ->
                    check_keys [ "source"; "description"; "revision" ] project;
                    let text field default =
                      match get field project with
                      | None -> default
                      | Some (TString value) -> value
                      | _ -> raise (Invalid "Project fields must be strings.")
                    in
                    let source = path ~base ~home (text "source" "") in
                    let project =
                      match
                        Project.make ~name:(Table.Key.to_string name) ~source
                          ~description:(text "description" "")
                          ~revision:(text "revision" "@")
                      with
                      | Ok project -> project
                      | Error error -> raise (Invalid error)
                    in
                    project :: entries
                | _ -> raise (Invalid "Each project must be a TOML table."))
              projects []
            |> List.sort (fun (a : Project.t) b -> String.compare a.name b.name)
        | Some _ -> raise (Invalid "projects must be a TOML table.")
      in
      let codex =
        match get "codex" table with
        | None -> empty.codex
        | Some (TTable defaults) ->
            check_keys [ "executable"; "gateway"; "reasoning_effort" ] defaults;
            let optional name =
              match get name defaults with
              | None -> None
              | Some (TString value) -> Some value
              | _ -> raise (Invalid "Codex defaults must be strings.")
            in
            let configured_path name = Option.map (path ~base ~home) (optional name) in
            let reasoning =
              Option.map
                (fun value ->
                  match Reasoning_effort.parse value with
                  | Ok effort -> effort
                  | Error error -> raise (Invalid error))
                (optional "reasoning_effort")
            in
            {
              executable = configured_path "executable";
              gateway_file = configured_path "gateway";
              reasoning;
            }
        | Some _ -> raise (Invalid "codex must be a TOML table.")
      in
      let workspace =
        match get "workspace" table with
        | None -> Workspace_defaults.empty
        | Some (TTable defaults) ->
            check_keys [ "jj"; "source"; "parent"; "revision"; "model" ] defaults;
            let optional name =
              match get name defaults with
              | None -> None
              | Some (TString value)
                when String.trim value <> ""
                     && String.length value <= 4096
                     && not
                          (String.exists
                             (fun c -> Char.code c < 32 || Char.code c = 127)
                             value) ->
                  Some value
              | _ ->
                  raise
                    (Invalid
                       "Workspace defaults must be nonempty strings without controls.")
            in
            let configured_path name = Option.map (path ~base ~home) (optional name) in
            let revision = optional "revision" in
            (match revision with
            | Some value when value.[0] = '-' || String.length value > 1024 ->
                raise
                  (Invalid
                     "Workspace revision must be an explicit revision, not an option.")
            | _ -> ());
            let model = optional "model" in
            Option.iter
              (fun model ->
                match
                  Model.set_model
                    (Model.make ~id:"config-validation" ~title:"" ~repository:"")
                    model
                with
                | Error _ -> raise (Invalid "Invalid workspace default model ID.")
                | Ok _ -> ())
              model;
            {
              Workspace_defaults.jj = configured_path "jj";
              source = configured_path "source";
              parent = configured_path "parent";
              revision;
              model;
            }
        | Some _ -> raise (Invalid "workspace must be a TOML table.")
      in
      let layout =
        match get "layout" table with
        | None -> Pane_layout.automatic
        | Some (TTable layout) -> (
            check_keys [ "board_width_percent"; "board_height_percent" ] layout;
            let percentage name =
              match get name layout with
              | None -> None
              | Some (TInt value) -> Some value
              | _ -> raise (Invalid "Layout percentages must be integers from 10 to 90.")
            in
            match
              Pane_layout.make_defaults
                ~board_width:(percentage "board_width_percent")
                ~board_height:(percentage "board_height_percent")
            with
            | Ok defaults -> defaults
            | Error error -> raise (Invalid error))
        | Some _ -> raise (Invalid "layout must be a TOML table.")
      in
      Ok { database; projects; codex; workspace; layout }
    with
    | Invalid message -> Error message
    | Toml.Parser.Error _ -> Error "Invalid TOML config. Source content was not printed."

let load ~home filename =
  try
    let fd =
      Unix.openfile filename [ Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC ] 0
    in
    let channel = Unix.in_channel_of_descr fd in
    let@ () = on_exit (fun () -> close_in_noerr channel) in
    if (Unix.fstat fd).Unix.st_kind <> Unix.S_REG then
      Error "Config must be a regular file."
    else
      let buffer = Bytes.create 65537 in
      let rec read offset =
        if offset = Bytes.length buffer then offset
        else
          let count = input channel buffer offset (Bytes.length buffer - offset) in
          if count = 0 then offset else read (offset + count)
      in
      let count = read 0 in
      parse
        ~base:(Filename.dirname (Unix.realpath filename))
        ~home
        (Bytes.sub_string buffer 0 count)
  with Unix.Unix_error _ | Sys_error _ -> Error "Cannot read config file."

let default_path ~home ~xdg =
  let base =
    match xdg with
    | Some directory when directory <> "" && not (Filename.is_relative directory) ->
        directory
    | _ -> Filename.concat home ".config"
  in
  Filename.concat base "factory-tui/config.toml"

let resolve_settings ~home ~xdg ~config ~no_config ~database =
  if no_config && config <> None then Error "--config and --no-config cannot be combined."
  else
    let loaded =
      if no_config then Ok empty
      else
        match config with
        | Some filename -> load ~home filename
        | None -> (
            let filename = default_path ~home ~xdg in
            try
              ignore (Unix.stat filename);
              load ~home filename
            with
            | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok empty
            | Unix.Unix_error _ -> Error "Cannot inspect default config file.")
    in
    match loaded with
    | Error error -> Error error
    | Ok config -> (
        try
          Ok
            {
              config with
              database =
                (match database with
                | None -> config.database
                | Some value -> Some (path ~base:(Sys.getcwd ()) ~home value));
            }
        with Invalid error -> Error error)

let resolve ~home ~xdg ~config ~no_config ~database =
  Result.map
    (fun settings -> settings.database)
    (resolve_settings ~home ~xdg ~config ~no_config ~database)
