type t = { database : string option }

let empty = { database = None }

exception Invalid of string

let path ~base ~home value =
  if value = "" || String.exists (fun c -> Char.code c < 32 || Char.code c = 127) value
  then raise (Invalid "Database path must not be empty or contain controls.");
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
                (Invalid "Unknown config field. Only [storage].database is supported."))
          table
      in
      let get name table = Table.find_opt (Table.Key.of_string name) table in
      check_keys [ "storage" ] table;
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
      Ok { database }
    with
    | Invalid message -> Error message
    | Toml.Parser.Error _ -> Error "Invalid TOML config. Source content was not printed."

let load ~home filename =
  try
    let fd =
      Unix.openfile filename [ Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC ] 0
    in
    let channel = Unix.in_channel_of_descr fd in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
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
            (Bytes.sub_string buffer 0 count))
  with Unix.Unix_error _ | Sys_error _ -> Error "Cannot read config file."

let default_path ~home ~xdg =
  let base =
    match xdg with
    | Some directory when directory <> "" && not (Filename.is_relative directory) ->
        directory
    | _ -> Filename.concat home ".config"
  in
  Filename.concat base "factory-tui/config.toml"

let resolve ~home ~xdg ~config ~no_config ~database =
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
            (match database with
            | None -> config.database
            | Some value -> Some (path ~base:(Sys.getcwd ()) ~home value))
        with Invalid error -> Error error)
