let limit = 1048576

let decode body =
  if String.length body > limit then Error "Gateway model response exceeds 1 MiB."
  else
    try
      let open Yojson.Basic.Util in
      let data = Yojson.Basic.from_string body |> member "data" |> to_list in
      if List.length data > 10000 then Error "Gateway returned too many models."
      else
        let models = List.map (fun item -> member "id" item |> to_string) data in
        let valid id =
          id <> ""
          && String.length id <= 256
          && id.[0] <> '-'
          && Uutf.String.fold_utf_8
               (fun valid _ -> function `Uchar _ -> valid | `Malformed _ -> false)
               true id
          && not (String.exists (fun c -> Char.code c <= 32 || Char.code c = 127) id)
        in
        if List.for_all valid models then Ok (List.sort_uniq String.compare models)
        else Error "Gateway returned an invalid model identifier."
    with Yojson.Json_error _ | Yojson.Basic.Util.Type_error _ ->
      Error "Gateway model response is not a valid model catalogue."

let url gateway =
  let base = Gateway.base_url gateway in
  let rec finish length =
    if length > 0 && base.[length - 1] = '/' then finish (length - 1) else length
  in
  String.sub base 0 (finish (String.length base)) ^ "/models"

let quote value =
  let buffer = Buffer.create (String.length value + 2) in
  Buffer.add_char buffer '"';
  String.iter
    (fun c ->
      if c = '"' || c = '\\' then Buffer.add_char buffer '\\';
      Buffer.add_char buffer c)
    value;
  Buffer.add_char buffer '"';
  Buffer.contents buffer

let response ~key (output : Command.output) =
  match output.status with
  | Unix.WEXITED 0 -> (
      match String.rindex_opt output.stdout '\n' with
      | None -> Error "Gateway did not return an HTTP status."
      | Some offset -> (
          let status =
            String.sub output.stdout (offset + 1)
              (String.length output.stdout - offset - 1)
          in
          let body = String.sub output.stdout 0 offset in
          match status with
          | "200" ->
              if Literal_search.contains (Literal_search.prepare key) body then
                Error "Gateway response contains credential material; output withheld."
              else
                Result.bind (decode body) (fun models ->
                    let secret = Literal_search.prepare key in
                    if List.exists (Literal_search.contains secret) models then
                      Error
                        "Gateway response contains credential material; output withheld."
                    else Ok models)
          | "401" | "403" ->
              Error
                "Gateway authentication failed. Check the API key and model-list access."
          | "404" -> Error "Gateway model endpoint was not found. Check the base URL."
          | "429" -> Error "Gateway rate-limited the model-list request."
          | _ -> Error "Gateway model-list request returned an unsuccessful HTTP status.")
      )
  | Unix.WEXITED 28 -> Error "Gateway model-list request timed out."
  | Unix.WEXITED 6 | Unix.WEXITED 7 ->
      Error "Cannot reach the gateway. Check its URL and connectivity."
  | Unix.WEXITED 60 -> Error "Gateway TLS certificate verification failed."
  | Unix.WEXITED 63 -> Error "Gateway model response exceeds 1 MiB."
  | _ ->
      Error "Gateway model-list transport failed. Response and diagnostics were withheld."

let fetch ~curl ~lookup gateway =
  match lookup (Gateway.key_environment gateway) with
  | None | Some "" -> Error "Gateway API key environment variable is not set."
  | Some key -> (
      if
        String.length key > 4096
        || String.exists (fun c -> Char.code c <= 32 || Char.code c >= 127) key
      then Error "Gateway API key has an invalid format."
      else
        let input =
          "url = "
          ^ quote (url gateway)
          ^ "\nheader = "
          ^ quote ("Authorization: Bearer " ^ key)
          ^ "\nheader = \"Accept: application/json\"\n"
        in
        (* The header uses stdin so the key is absent from process arguments and files. *)
        match
          Command.run_input ~input ~executable:curl
            ~arguments:
              [
                "--disable";
                "--silent";
                "--globoff";
                "--proto";
                "=http,https";
                "--connect-timeout";
                "5";
                "--max-time";
                "10";
                "--max-filesize";
                string_of_int limit;
                "--write-out";
                "\n%{http_code}";
                "--config";
                "-";
              ]
            ~directory:(Sys.getcwd ()) ~timeout:12. ~max_output:(limit + 4)
        with
        | Error _ -> Error "Gateway model-list transport failed or exceeded its limits."
        | Ok output -> response ~key output)
