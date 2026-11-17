let identifier value =
  value <> ""
  && String.trim value = value
  && value.[0] <> '-'
  && String.length value <= 256
  && not (String.exists (fun c -> Char.code c < 32 || Char.code c = 127) value)

let invocation ~executable ~directory ~model ~thread_id =
  if Filename.is_relative executable || String.contains executable '\000' then
    Error "Codex executable must be an absolute path without null bytes."
  else if Filename.is_relative directory || String.contains directory '\000' then
    Error "Codex directory must be an existing absolute path."
  else if not (identifier model) then Error "Invalid Codex model ID."
  else if Option.fold ~none:false ~some:(fun id -> not (identifier id)) thread_id then
    Error "Invalid explicit Codex thread ID."
  else
    try
      if not (Sys.is_directory directory) then Error "Codex directory does not exist."
      else
        let common =
          [
            "--json";
            "--ignore-user-config";
            "--model";
            model;
            "-c";
            {|approval_policy="never"|};
            "-c";
            {|sandbox_mode="read-only"|};
          ]
        in
        let arguments =
          match thread_id with
          | None -> [ "exec"; "--color"; "never"; "--cd"; directory ] @ common @ [ "-" ]
          | Some id -> [ "exec"; "resume" ] @ common @ [ id; "-" ]
        in
        Ok (Process.defaults ~executable ~arguments ~directory)
    with Sys_error _ -> Error "Cannot inspect Codex directory."

let with_gateway config gateway =
  let quoted value = Toml.Printer.string_of_value (Toml.Types.TString value) in
  let overrides =
    [
      {|model_provider="factory_gateway"|};
      {|model_providers.factory_gateway.name="Factory gateway"|};
      "model_providers.factory_gateway.base_url=" ^ quoted (Gateway.base_url gateway);
      "model_providers.factory_gateway.env_key="
      ^ quoted (Gateway.key_environment gateway);
      {|model_providers.factory_gateway.wire_api="responses"|};
      {|model_providers.factory_gateway.requires_openai_auth=false|};
    ]
  in
  let overrides = List.concat_map (fun value -> [ "-c"; value ]) overrides in
  let arguments =
    match config.Process.arguments with
    | "exec" :: "resume" :: rest -> [ "exec"; "resume" ] @ overrides @ rest
    | "exec" :: rest -> ("exec" :: overrides) @ rest
    | rest -> overrides @ rest
  in
  { config with arguments }
