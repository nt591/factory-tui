open Factory_tui

let check name condition = if not condition then failwith name

let payload output =
  Yojson.Basic.to_string
    (`Assoc
       [
         ("type", `String "command_execution");
         ("status", `String "completed");
         ("command", `String "fixture");
         ("aggregated_output", `String output);
       ])

let measure () =
  let tools =
    List.init 200 (fun index ->
        ( string_of_int index,
          payload (String.concat "\n" (List.init 100 (Printf.sprintf "Output %04d"))) ))
  in
  let cache = Tool_cache.create () in
  let document = Tool_cache.update cache ~task_id:"task" tools in
  let scan document =
    List.iter
      (fun (id, payload) ->
        ignore
          (match document with
          | None -> Tool_activity.describe ~id payload
          | Some doc -> Tool_cache.describe doc ~id ~payload))
      tools
  in
  scan (Some document);
  let time action =
    let start = Unix.gettimeofday () in
    for _ = 1 to 20 do
      action ()
    done;
    (Unix.gettimeofday () -. start) *. 1000.
  in
  Printf.printf
    "200 tools, 100 output lines each, 20 readable-content passes.\n\
     Full decoding: %.3f ms; cached descriptions: %.3f ms.\n\
     Excludes wrapping, image construction, origin labels, terminal output.\n"
    (time (fun () -> scan None))
    (time (fun () -> scan (Some document)))

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else
    let cache = Tool_cache.create () in
    let old = payload "Old output" and stable = payload "Stable output" in
    let tools = [ ("run/old", old); ("run/stable", stable) ] in
    let doc = Tool_cache.update cache ~task_id:"task" tools in
    let description = Tool_cache.describe doc ~id:"run/stable" ~payload:stable in
    let raw = Tool_cache.raw doc ~id:"run/stable" ~payload:stable in
    check "unchanged tool list reuses document"
      (Tool_cache.update cache ~task_id:"task" tools == doc);
    check "readable and raw results are stable cache entries"
      (Tool_cache.describe doc ~id:"run/stable" ~payload:stable == description
      && Tool_cache.raw doc ~id:"run/stable" ~payload:stable == raw);
    let replacement = payload "New output" in
    let changed =
      Tool_cache.update cache ~task_id:"task"
        [ ("run/old", replacement); ("run/stable", stable) ]
    in
    check "payload update retains other decoded tool"
      (Tool_cache.describe changed ~id:"run/stable" ~payload:stable == description);
    check "replacement payload produces current output"
      (List.mem "New output"
         (Tool_cache.describe changed ~id:"run/old" ~payload:replacement).details);
    check "cached descriptions equal uncached decoder"
      (Tool_cache.describe changed ~id:"run/old" ~payload:replacement
      = Tool_activity.describe ~id:"run/old" replacement);
    ignore (Tool_cache.update cache ~task_id:"task" [ ("run/old", replacement) ]);
    let restored = Tool_cache.update cache ~task_id:"task" tools in
    check "removed items do not accumulate in later document"
      (Tool_cache.describe restored ~id:"run/stable" ~payload:stable != description);
    let other = Tool_cache.update cache ~task_id:"other" tools in
    check "task switch discards old descriptions"
      (Tool_cache.describe other ~id:"run/stable" ~payload:stable
      != Tool_cache.describe restored ~id:"run/stable" ~payload:stable);
    Tool_cache.clear cache;
    let cleared = Tool_cache.update cache ~task_id:"other" tools in
    check "clear releases retained cache" (cleared != other);
    check "stale-document payload lookup cannot return stale output"
      (List.mem "New output"
         (Tool_cache.describe doc ~id:"run/old" ~payload:replacement).details);
    let task = Model.make ~id:"task" ~title:"Inspect" ~repository:"fixture" in
    let task = { task with tools } in
    let rows ?tools raw =
      Activity_content.lines ?tools ~now:0. ~expanded:true ~raw ~waiting:false (Some task)
    in
    List.iter
      (fun raw ->
        check "cached Activity content equals uncached content"
          (rows ~tools:doc raw = rows raw))
      [ false; true ];
    let shapes =
      [
        "legacy lines\nremain";
        "{";
        "[]";
        {|{"type":"mcp_tool_call","server":"fixture","tool":"read","status":"failed","error":{"message":"denied"}}|};
        {|{"type":"file_change","changes":[{"kind":"add","path":"x.ml"}],"status":"completed"}|};
        {|{"type":"future_tool","retained":"raw-extra"}|};
      ]
    in
    List.iteri
      (fun index payload ->
        let id = string_of_int index in
        let doc = Tool_cache.update cache ~task_id:"shapes" [ (id, payload) ] in
        check "cache preserves known and legacy decoder behavior"
          (Tool_cache.describe doc ~id ~payload = Tool_activity.describe ~id payload
          && Tool_cache.raw doc ~id ~payload = Tool_activity.raw payload))
      shapes;
    let recorded : Model.run_record =
      {
        run_id = "run";
        harness = Model.Codex;
        model = "captured-model";
        started_at = 0.;
        ended_at = Some 1.;
        status = Model.Completed;
        simulated = false;
        policy = Model.Read_only;
      }
    in
    let recorded_task =
      { task with tools = [ ("run/stable", stable) ]; runs = [ recorded ] }
    in
    let origin_document = Tool_cache.update cache ~task_id:task.id recorded_task.tools in
    let origin before =
      Activity_content.lines ~tools:origin_document ~now:0. ~expanded:true ~raw:false
        ~waiting:false (Some before)
      |> String.concat "\n"
    in
    check "cached payload retains current recorded origin independently of next settings"
      (Controller.contains
         (origin { recorded_task with model = "next-model" })
         "Source run: run / Codex / captured-model / live / read-only");
    check "cached tool origin follows newly supplied run records not an old cache"
      (Controller.contains
         (origin { recorded_task with runs = [] })
         "Source run: not recorded");
    let controller = Controller.create ~external_events:true () in
    controller.tasks <- [ task ];
    controller.selected <- task.id;
    controller.zoom <- true;
    controller.activity_expanded <- true;
    controller.focus <- Controller.Activity;
    controller.tools_expanded <- true;
    let saved = Controller.snapshot controller in
    ignore (Ui.render controller ~width:120 ~height:36);
    let rendered = Tool_cache.update controller.tool_cache ~task_id:task.id tools in
    let decoded = Tool_cache.describe rendered ~id:"run/stable" ~payload:stable in
    ignore (Ui.render controller ~width:120 ~height:36);
    check "renderer reuses descriptions without saved mutations"
      (Tool_cache.describe
         (Tool_cache.update controller.tool_cache ~task_id:task.id tools)
         ~id:"run/stable" ~payload:stable
       == decoded
      && Controller.snapshot controller = saved);
    Printf.printf "Passed tool decoding cache checks. Pure payloads/rendering only.\n"
