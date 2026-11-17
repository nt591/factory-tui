let build ~executable ~directory ~model ~thread_id ~gateway_file =
  match Codex.invocation ~executable ~directory ~model ~thread_id with
  | Error error -> Error error
  | Ok invocation ->
      let configured =
        match gateway_file with
        | None -> Ok invocation
        | Some filename -> (
            match Gateway.load filename with
            | Error error -> Error error
            | Ok gateway -> Ok (Codex.with_gateway invocation gateway))
      in
      Result.map
        (fun (config : Process.config) ->
          `Assoc
            [
              ("mode", `String "dry-run");
              ("executable", `String config.executable);
              ("arguments", `List (List.map (fun arg -> `String arg) config.arguments));
              ("directory", `String config.directory);
              ("timeout_seconds", `Float config.timeout);
              ("prompt_source", `String "stdin");
              ("starts_process", `Bool false);
              ("reads_credentials", `Bool false);
              ("opens_database", `Bool false);
              ("compatibility", `String "unverified");
            ])
        configured
