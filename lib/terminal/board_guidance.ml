type action = Create_workspace | Create_demo | Clear_filters | Open_board
type t = { title : string; lines : string list; button : string; action : action }

let empty ~live ~has_tasks ~archived ~filtered =
  if filtered then
    {
      title = "No matching tasks";
      lines =
        [
          "Search or repository filters hide this board.";
          "The selected task chat remains available.";
        ];
      button = "[Clear filters / b]";
      action = Clear_filters;
    }
  else if archived then
    {
      title = "Archive is empty";
      lines =
        [
          "Only tasks you accept move to Archive.";
          "Ready means ready for review, not automatically Done.";
        ];
      button = "[Open session board / b]";
      action = Open_board;
    }
  else if live then
    {
      title = (if has_tasks then "No active tasks" else "Your factory starts here");
      lines =
        [
          "1. Describe a task in the current folder or an isolated workspace.";
          "2. Enter sends the task and starts its agent.";
          "3. Reply with i then Enter; x stops a run.";
          "4. Review changes with v; archive Ready work with Ctrl-A.";
          "Enter sends work; startup starts no agent.";
          "? opens help and settings. Workspace defaults live in TOML.";
        ];
      button = "[Create workspace task / W or n]";
      action = Create_workspace;
    }
  else
    {
      title = "No active tasks";
      lines =
        [
          "This launch uses simulation; no model is called.";
          "Create a demo task, then s streams simulated updates.";
          "W creates a real workspace task when SQLite is configured.";
        ];
      button = "[Create demo task / n]";
      action = Create_demo;
    }
