open Scope

type t = { base_url : string; key_environment : string }

let base_url t = t.base_url
let key_environment t = t.key_environment
let letter = function 'A' .. 'Z' | 'a' .. 'z' | '_' -> true | _ -> false
let digit = function '0' .. '9' -> true | _ -> false

let variable name =
  String.length name > 0
  && String.length name <= 256
  && letter name.[0]
  && String.for_all (fun c -> letter c || digit c) name

let hex = function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false

let escapes value =
  let rec loop i =
    if i >= String.length value then true
    else if value.[i] = '%' then
      i + 2 < String.length value && hex value.[i + 1] && hex value.[i + 2] && loop (i + 3)
    else loop (i + 1)
  in
  loop 0

let authority url =
  match String.index_opt url ':' with
  | Some start when start + 2 < String.length url && String.sub url (start + 1) 2 = "//"
    ->
      let start = start + 3 in
      let finish =
        match String.index_from_opt url start '/' with
        | None -> String.length url
        | Some i -> i
      in
      Some (String.sub url start (finish - start))
  | _ -> None

let valid_host host =
  if String.contains host ':' then
    try
      ignore (Unix.inet_addr_of_string host);
      true
    with Failure _ -> false
  else
    let labels = String.split_on_char '.' host in
    String.length host <= 253
    && List.for_all
         (fun label ->
           String.length label > 0
           && String.length label <= 63
           && label.[0] <> '-'
           && label.[String.length label - 1] <> '-'
           && String.for_all
                (function
                  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' -> true | _ -> false)
                label)
         labels

let valid_authority value =
  let valid_port port =
    port <> "" && String.for_all digit port
    && match int_of_string_opt port with Some n -> n > 0 && n <= 65535 | None -> false
  in
  if String.starts_with ~prefix:"[" value then
    match String.index_opt value ']' with
    | None -> false
    | Some ending ->
        let remainder =
          String.sub value (ending + 1) (String.length value - ending - 1)
        in
        remainder = ""
        || String.starts_with ~prefix:":" remainder
           && valid_port (String.sub remainder 1 (String.length remainder - 1))
  else
    match String.split_on_char ':' value with
    | [ _ ] -> true
    | [ _; port ] -> valid_port port
    | _ -> false

let make ~base_url ~key_environment =
  if not (variable key_environment) then
    Error "Gateway key reference must be an environment variable name."
  else if
    String.length base_url > 4096
    || String.exists
         (fun c -> Char.code c <= 32 || Char.code c >= 127 || c = '\\')
         base_url
    || not (escapes base_url)
  then Error "Gateway URL contains invalid characters."
  else if String.contains base_url '?' || String.contains base_url '#' then
    Error "Gateway URL must not contain query parameters or a fragment."
  else
    try
      let uri = Uri.of_string base_url in
      match (authority base_url, Uri.host uri, Uri.scheme uri) with
      | Some authority, Some raw_host, Some scheme ->
          let host =
            if
              String.starts_with ~prefix:"[" raw_host
              && String.ends_with ~suffix:"]" raw_host
            then String.sub raw_host 1 (String.length raw_host - 2)
            else raw_host
          in
          let scheme = String.lowercase_ascii scheme in
          let local =
            List.mem (String.lowercase_ascii host) [ "localhost"; "127.0.0.1"; "::1" ]
          in
          let port_valid =
            match Uri.port uri with
            | None -> not (String.ends_with ~suffix:":" authority)
            | Some port -> port > 0 && port <= 65535
          in
          if
            authority = "" || String.contains authority '@'
            || String.contains authority '%'
            || Uri.userinfo uri <> None
          then Error "Gateway URL must not contain credentials."
          else if
            (not (valid_host host)) || (not port_valid) || not (valid_authority authority)
          then Error "Gateway URL host or port is invalid."
          else if scheme <> "https" && not (scheme = "http" && local) then
            Error "Gateway requires HTTPS except on loopback."
          else Ok { base_url; key_environment }
      | _ -> Error "Gateway URL requires a scheme and host."
    with Invalid_argument _ | Failure _ -> Error "Gateway URL is invalid."

exception Invalid

let parse_environment ~lookup source =
  if String.length source > 65536 then Error "Gateway config exceeds 64 KiB."
  else
    try
      let table =
        match Toml.Parser.from_string source with
        | `Ok table -> table
        | `Error _ -> raise Invalid
      in
      let open Toml.Types in
      if Table.cardinal table <> 2 then raise Invalid;
      let value name =
        match Table.find_opt (Table.Key.of_string name) table with
        | Some (TString value) -> value
        | _ -> raise Invalid
      in
      let base_url =
        match Table.find_opt (Table.Key.of_string "base_url_environment") table with
        | None -> Ok (value "base_url")
        | Some (TString name) when variable name -> (
            match lookup name with
            | Some url when url <> "" -> Ok url
            | _ -> Error "Gateway base URL environment variable is not set.")
        | _ -> Error "Gateway base URL reference must be an environment variable name."
      in
      Result.bind base_url (fun base_url ->
          make ~base_url ~key_environment:(value "key_environment"))
    with Invalid | Toml.Parser.Error _ ->
      Error
        "Invalid gateway config; expected base_url or base_url_environment, plus \
         key_environment."

let parse source = parse_environment ~lookup:Sys.getenv_opt source

let load filename =
  try
    let fd =
      Unix.openfile filename [ Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC ] 0
    in
    let channel = Unix.in_channel_of_descr fd in
    let@ () = on_exit (fun () -> close_in_noerr channel) in
    if (Unix.fstat fd).Unix.st_kind <> Unix.S_REG then
      Error "Gateway config must be a regular file."
    else
      let bytes = Bytes.create 65537 in
      let rec read offset =
        if offset = Bytes.length bytes then offset
        else
          let count = input channel bytes offset (Bytes.length bytes - offset) in
          if count = 0 then offset else read (offset + count)
      in
      let count = read 0 in
      parse (Bytes.sub_string bytes 0 count)
  with Unix.Unix_error _ | Sys_error _ -> Error "Cannot read gateway config."
