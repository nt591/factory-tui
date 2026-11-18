open Model

let run_status = function
  | Running -> "running"
  | Completed -> "completed"
  | Run_failed -> "failed"
  | Stopped -> "interrupted"
  | Awaiting_input -> "needs input"

let run_line ~now (record : run_record) =
  "run " ^ record.run_id ^ ": " ^ harness_label record.harness ^ " / " ^ record.model
  ^ " / " ^ run_status record.status
  ^ (if record.simulated then " / simulated" else " / live")
  ^ (match record.policy with
    | Read_only -> " / read-only"
    | Workspace_write -> " / workspace-write")
  ^ " / " ^ Run_time.describe ~now record

let tool_origin runs id =
  let source =
    List.fold_left
      (fun (source : run_record option) (record : run_record) ->
        if String.starts_with ~prefix:(record.run_id ^ "/") id then
          match source with
          | Some previous
            when String.length previous.run_id >= String.length record.run_id ->
              source
          | _ -> Some record
        else source)
      None runs
  in
  match source with
  | None -> "Source run: not recorded"
  | Some record -> (
      "Source run: " ^ record.run_id ^ " / " ^ harness_label record.harness ^ " / "
      ^ record.model
      ^ (if record.simulated then " / simulated" else " / live")
      ^
      match record.policy with
      | Read_only -> " / read-only"
      | Workspace_write -> " / workspace-write")

let describe tools id payload =
  match tools with
  | None -> Tool_activity.describe ~id payload
  | Some tools -> Tool_cache.describe tools ~id ~payload

let tool_lines ~tools ~runs ~raw (id, payload) =
  let activity = describe tools id payload in
  let details =
    if not raw then activity.details
    else
      match tools with
      | None -> Tool_activity.raw payload
      | Some tools -> Tool_cache.raw tools ~id ~payload
  in
  (activity.summary :: details) @ [ tool_origin runs id; "" ]

let lines ?tools ~now ~expanded ~raw ~waiting = function
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
           :: List.concat_map (tool_lines ~tools ~runs:task.runs ~raw) task.tools
         else
           let id, payload = List.hd (List.rev task.tools) in
           [
             Printf.sprintf "▸ %d tool items / t expands" (List.length task.tools);
             "Latest update: " ^ (describe tools id payload).summary;
             tool_origin task.runs id;
           ])
      @
      if task.runs = [] then []
      else
        [ ""; "RUN HISTORY / newest first" ]
        @ List.map (run_line ~now) (List.rev task.runs)
