open Model

let run_status = function
  | Running -> "running"
  | Completed -> "completed"
  | Run_failed -> "failed"
  | Stopped -> "interrupted"
  | Awaiting_input -> "needs input"

let run_line (record : run_record) =
  "run " ^ record.run_id ^ ": " ^ harness_label record.harness ^ " / " ^ record.model
  ^ " / " ^ run_status record.status
  ^ (if record.simulated then " / simulated" else " / live")
  ^
  match record.policy with
  | Read_only -> " / read-only"
  | Workspace_write -> " / workspace-write"

let tool_lines ~raw (id, payload) =
  let activity = Tool_activity.describe ~id payload in
  (activity.summary :: (if raw then Tool_activity.raw payload else activity.details))
  @ [ "" ]

let lines ~expanded ~raw ~waiting = function
  | None -> [ "No task selected." ]
  | Some (task : task) ->
      [ task.title; "repo: " ^ task.repository ]
      @ (match task.workspace with
        | None -> [ "workspace: not attached" ]
        | Some workspace ->
            [ "workspace: " ^ workspace.directory; "base: " ^ workspace.base ])
      @ [
          ("run: " ^ match task.active with None -> "idle" | Some run -> run.id);
          (if waiting then "Waiting for previous workspace process cleanup." else "");
          "next: " ^ harness_label task.harness ^ " / " ^ task.model;
          "updates: " ^ string_of_int task.revision;
          "";
        ]
      @ (if task.tools = [] then [ "No tool activity yet." ]
         else if expanded then
           Printf.sprintf "▾ %d tool items / %s / T toggles raw" (List.length task.tools)
             (if raw then "raw" else "readable")
           :: List.concat_map (tool_lines ~raw) task.tools
         else [ Printf.sprintf "▸ %d tool items / t expands" (List.length task.tools) ])
      @ [ "" ] @ List.map run_line task.runs
