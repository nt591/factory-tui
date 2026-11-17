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
