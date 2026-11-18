open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let describe payload = Tool_activity.describe ~id:"run/item" payload

let () =
  let command =
    describe
      {|{"type":"command_execution","id":"cmd","command":"dune runtest","status":"completed","exit_code":0,"aggregated_output":"check one\ncheck two"}|}
  in
  check "command status and exit displayed"
    (command.summary = "Command / completed / exit 0");
  check "command displayed without JSON escaping"
    (List.hd command.details = "$ dune runtest");
  check "command output preserves logical lines"
    (List.mem "check one" command.details && List.mem "check two" command.details);
  check "harness item identity shown" (List.mem "Item: cmd" command.details);
  let failed =
    describe
      {|{"type":"command_execution","command":"false","status":"failed","exit_code":1,"aggregated_output":""}|}
  in
  check "failed exit preserved" (failed.summary = "Command / failed / exit 1");
  check "empty output distinguished" (List.mem "Output: empty" failed.details);
  let unknown = describe {|{"type":"command_execution"}|} in
  check "missing status never implies success"
    (unknown.summary = "Command / status unknown");
  check "missing output distinguished" (List.mem "Output: not supplied" unknown.details);
  let mcp =
    describe
      {|{"type":"mcp_tool_call","id":"mcp","server":"files","tool":"read","status":"completed","arguments":{"path":"a.ml"},"result":{"text":"file contents"}}|}
  in
  check "MCP target and status readable" (mcp.summary = "MCP files/read / completed");
  check "MCP arguments and result remain inspectable"
    (List.mem "Arguments:" mcp.details && List.mem "Result:" mcp.details);
  let error =
    describe {|{"type":"mcp_tool_call","status":"failed","error":{"message":"denied"}}|}
  in
  check "MCP error retained"
    (Controller.contains (String.concat "\n" error.details) "denied");
  let files =
    describe
      {|{"type":"file_change","status":"completed","changes":[{"kind":"add","path":"new.ml"},{"kind":"update","path":"existing.ml"}]}|}
  in
  check "file operations readable"
    (List.mem "add new.ml" files.details && List.mem "update existing.ml" files.details);
  check "file status copied not inferred" (files.summary = "Files / completed");
  let fallback = describe "Inspect files\nLegacy fixture output" in
  check "legacy non-JSON survives"
    (fallback.details = [ "Inspect files"; "Legacy fixture output" ]);
  let future = describe {|{"type":"future_tool","payload":{"nonstandard":"retained"}}|} in
  check "unknown tool payload retained"
    (Controller.contains (String.concat "\n" future.details) "retained");
  check "raw known payload includes unknown fields"
    (Controller.contains
       (String.concat "\n"
          (Tool_activity.raw {|{"type":"command_execution","future":"retained"}|}))
       "retained");
  List.iter
    (fun source -> ignore (describe source))
    [ "[]"; "null"; "123"; "{"; {|{"type":false}|} ];
  check "unexpected JSON shapes do not raise" true;
  let t = Controller.create ~external_events:true () in
  let task = Model.make ~id:"task" ~title:"Activity fixture" ~repository:"fixture" in
  t.tasks <-
    [
      {
        task with
        tools =
          [
            ( "run/item",
              {|{"type":"command_execution","id":"command","command":"inspect workspace","status":"completed","exit_code":0,"aggregated_output":"Output line one\nOutput line two","future_field":"diagnostic-value"}|}
            );
          ];
      };
    ];
  t.selected <- task.id;
  t.zoom <- true;
  t.focus <- Controller.Activity;
  let rendered () =
    let frame = Ui.render t ~width:120 ~height:36 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
    Buffer.contents buffer
  in
  let saved = Controller.snapshot t in
  check "tool group initially collapsed"
    (not (Controller.contains (rendered ()) "inspect workspace"));
  check "collapsed group shows latest status without payload details"
    (Controller.contains (rendered ()) "Latest update: Command"
    && not (Controller.contains (rendered ()) "diagnostic-value"));
  Controller.key t (`ASCII 't', []);
  let readable = rendered () in
  check "readable activity rendered"
    (Controller.contains readable "$ inspect workspace"
    && Controller.contains readable "exit 0");
  check "raw-only field hidden in readable mode"
    (not (Controller.contains readable "diagnostic-value"));
  Controller.key t (`ASCII 'T', []);
  check "T reveals preserved raw diagnostic fields"
    (t.raw_tools && Controller.contains (rendered ()) "diagnostic-value");
  Controller.key t (`ASCII 'T', []);
  check "T restores readable mode"
    ((not t.raw_tools) && Controller.contains (rendered ()) "$ inspect workspace");
  check "activity toggles do not change persisted data" (Controller.snapshot t = saved);
  check "activity toggles cannot start a run"
    ((Option.get (Controller.selected t)).active = None);
  List.iter
    (fun (width, height) ->
      let frame = Ui.render t ~width ~height in
      check "tool layout bounds"
        (Notty.I.width frame.image = width && Notty.I.height frame.image = height))
    [ (1, 1); (20, 8); (60, 20); (120, 36); (180, 50) ];
  Printf.printf "Passed %d tool activity checks. Rendering only; no tool execution.\n"
    !checks
