let optional_string = function None -> `Null | Some value -> `String value
let optional_int = function None -> `Null | Some value -> `Int value

let describe (settings : Config.t) =
  `Assoc
    [
      ("valid", `Bool true);
      ( "workspace_mode",
        `String
          (match settings.workspace.mode with
          | Existing -> "existing"
          | Folder -> "folder"
          | Greenfield -> "greenfield") );
      ("opens_database", `Bool false);
      ("starts_process", `Bool false);
      ("checks_path_existence", `Bool false);
      ("checks_gateway_compatibility", `Bool false);
      ("storage", `Assoc [ ("database", optional_string settings.database) ]);
      ( "projects",
        `List
          (List.map
             (fun (project : Project.t) ->
               `Assoc
                 [
                   ("name", `String project.name);
                   ("source", `String project.source);
                   ("description", `String project.description);
                   ("revision", `String project.revision);
                 ])
             settings.projects) );
      ( "codex",
        `Assoc
          [
            ("executable", optional_string settings.codex.executable);
            ("gateway", optional_string settings.codex.gateway_file);
            ( "reasoning_effort",
              optional_string (Option.map Reasoning_effort.label settings.codex.reasoning)
            );
            ("enables_live_mode", `Bool false);
          ] );
      ( "workspace",
        `Assoc
          [
            ("jj", optional_string settings.workspace.jj);
            ("source", optional_string settings.workspace.source);
            ("parent", optional_string settings.workspace.parent);
            ("revision", optional_string settings.workspace.revision);
            ("model", optional_string settings.workspace.model);
          ] );
      ( "layout",
        `Assoc
          [
            ("board_width_percent", optional_int (Pane_layout.board_width settings.layout));
            ( "board_height_percent",
              optional_int (Pane_layout.board_height settings.layout) );
          ] );
    ]
