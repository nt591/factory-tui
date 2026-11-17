open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error
let completed = "printf '%s\\n' '{\"type\":\"turn.completed\"}'\n"

let with_temp fn =
  let directory = Filename.temp_file "factory-process" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let directory = Unix.realpath directory in
  Fun.protect
    ~finally:(fun () ->
      Array.iter
        (fun name -> Sys.remove (Filename.concat directory name))
        (Sys.readdir directory);
      Unix.rmdir directory)
    (fun () -> fn directory)

let () =
  check "unknown harness event retained"
    (let decoded = ok (Harness.decode {|{"type":"future","payload":123}|}) in
     decoded.event = None
     && decoded.raw = Yojson.Basic.from_string {|{"type":"future","payload":123}|});
  check "known event fields validated"
    (Result.is_error (Harness.decode {|{"type":"thread.started"}|}));
  check "malformed JSON rejected" (Result.is_error (Harness.decode "bad"));
  check "thread identity decoded"
    ((ok (Harness.decode {|{"type":"thread.started","thread_id":"thread"}|})).event
   = Some (Model.Thread_started "thread"));
  check "tool payload retained"
    (match
       (ok
          (Harness.decode
             {|{"type":"item.completed","item":{"type":"command_execution","id":"tool","exit_code":0,"aggregated_output":"pass"}}|}))
         .event
     with
    | Some (Model.Tool ("tool", text)) -> String.length text > 30
    | _ -> false);
  with_temp (fun directory ->
      let serial = ref 0 in
      let fixture text =
        incr serial;
        let filename =
          Filename.concat directory (Printf.sprintf "fixture-%d.sh" !serial)
        in
        let channel = open_out filename in
        output_string channel ("#!/bin/sh\n" ^ text);
        close_out channel;
        Unix.chmod filename 0o700;
        filename
      in
      let config text =
        Process.defaults ~executable:(fixture text) ~arguments:[] ~directory
      in
      let run ?(prompt = "fixture prompt") ?(cancelled = fun () -> false)
          ?(on_event = fun _ -> ()) cfg =
        Process.run cfg ~prompt ~cancelled ~on_event
      in
      let output = ref [] in
      let cfg =
        config
          ("cat > prompt.txt\n\
            printf '%s\\n' '{\"type\":\"turn.started\"}'\n\
            printf '%s\\n' \
            '{\"type\":\"item.updated\",\"item\":{\"type\":\"agent_message\",\"id\":\"reply\",\"text\":\"hello\"}}'\n\
            sleep 0.1\n" ^ completed)
      in
      let result = ok (run ~on_event:(fun decoded -> output := decoded :: !output) cfg) in
      check "successful fixture requires completion"
        (result.succeeded && result.events = 3 && result.status = Unix.WEXITED 0);
      check "prompt delivered through stdin in selected directory"
        (let channel = open_in (Filename.concat directory "prompt.txt") in
         let text = really_input_string channel (in_channel_length channel) in
         close_in channel;
         text = "fixture prompt");
      check "message streamed"
        (List.exists
           (fun (decoded : Harness.decoded) ->
             decoded.event = Some (Model.Message ("reply", "hello")))
           !output);
      let marker = Filename.concat directory "callback-delivered" in
      let result =
        ok
          (run
             ~on_event:(fun _ ->
               let channel = open_out marker in
               close_out channel)
             (config
                (completed
               ^ "attempts=0\n\
                  while [ ! -f callback-delivered ]; do\n\
                 \  attempts=$((attempts + 1))\n\
                 \  [ $attempts -lt 200 ] || exit 1\n\
                 \  sleep 0.01\n\
                  done\n")))
      in
      check "callback arrives before process exit"
        (result.succeeded && Sys.file_exists marker);
      check "zero exit alone not success" (not (ok (run (config "exit 0\n"))).succeeded);
      check "completion with nonzero exit not success"
        (not (ok (run (config (completed ^ "exit 3\n")))).succeeded);
      let failed =
        config
          ("printf '%s\\n' '{\"type\":\"error\",\"message\":\"fixture failure\"}'\n"
         ^ completed)
      in
      check "fatal events stay fatal" (not (ok (run failed)).succeeded);
      let cfg =
        config ("dd if=/dev/zero bs=8192 count=32 1>&2 2>/dev/null\n" ^ completed)
      in
      let result = ok (run cfg) in
      check "stderr drained concurrently"
        (result.succeeded && result.stderr_bytes = 262144);
      let cfg = config "printf 'bad json\\n'\nsleep 10\n" in
      let before = Unix.gettimeofday () in
      check "invalid event stops child" (Result.is_error (run cfg));
      check "invalid event cleanup bounded" (Unix.gettimeofday () -. before < 1.);
      let cfg = config "printf '%0100d' 0\nsleep 10\n" in
      check "unterminated oversized line stopped"
        (Result.is_error (run { cfg with max_line = 32 }));
      let cfg =
        config ("dd if=/dev/zero bs=8192 count=2 1>&2 2>/dev/null\n" ^ completed)
      in
      check "stderr retention limit enforced"
        (Result.is_error (run { cfg with max_stream = 32 }));
      let cfg = config (completed ^ completed ^ completed) in
      check "event count bound enforced"
        (Result.is_error (run { cfg with max_events = 2 }));
      let cfg = config (completed ^ "sleep 10\n") in
      let before = Unix.gettimeofday () in
      check "callback exceptions stop run"
        (Result.is_error (run ~on_event:(fun _ -> failwith "test") cfg));
      check "callback failure teardown bounded" (Unix.gettimeofday () -. before < 1.);
      let before = Unix.gettimeofday () in
      check "timeout enforced"
        (Result.is_error (run { (config "sleep 10\n") with timeout = 0.1 }));
      check "timeout teardown bounded" (Unix.gettimeofday () -. before < 1.);
      let before = Unix.gettimeofday () in
      let result =
        ok
          (run
             ~cancelled:(fun () -> Unix.gettimeofday () -. before > 0.1)
             (config "sleep 10\n"))
      in
      check "cancellation reported" (result.interrupted && not result.succeeded);
      check "cancellation teardown bounded" (Unix.gettimeofday () -. before < 1.);
      let cfg = config ("sleep 10 &\n" ^ completed ^ "exit 0\n") in
      let before = Unix.gettimeofday () in
      check "parent exit drains inherited pipes" (ok (run cfg)).succeeded;
      check "descendant cleanup bounded" (Unix.gettimeofday () -. before < 1.);
      let cfg = config "touch must-not-exist\n" in
      check "prelaunch cancel refuses process"
        (Result.is_error (run ~cancelled:(fun () -> true) cfg));
      check "prelaunch cancel has no effect"
        (not (Sys.file_exists (Filename.concat directory "must-not-exist")));
      check "relative executable refused"
        (Result.is_error (run { cfg with executable = "sh" }));
      check "invalid limits refused"
        (Result.is_error (run { cfg with timeout = Float.nan }));
      check "oversized prompt refused"
        (Result.is_error (run ~prompt:(String.make 1048577 'x') cfg));
      check "missing executable reported"
        (Result.is_error
           (run { cfg with executable = Filename.concat directory "absent" }));
      check "final record without newline parsed"
        (ok (run (config "printf '%s' '{\"type\":\"turn.completed\"}'"))).succeeded;
      let handle =
        Run_handle.start (config (completed ^ "sleep 0.1\n")) ~prompt:"fixture"
      in
      let deadline = Unix.gettimeofday () +. 2. in
      while Run_handle.outcome handle = None && Unix.gettimeofday () < deadline do
        Thread.delay 0.01
      done;
      check "run handle publishes completion"
        (match Run_handle.outcome handle with
        | Some (Ok result) -> result.succeeded
        | _ -> false);
      check "run handle retains ordered output" (List.length (Run_handle.drain handle) = 1);
      check "drain consumes delivered events" (Run_handle.drain handle = []);
      Run_handle.close handle;
      let handle =
        Run_handle.start ~capacity:1
          (config (completed ^ completed ^ "sleep 10\n"))
          ~prompt:"fixture"
      in
      let deadline = Unix.gettimeofday () +. 2. in
      while Run_handle.outcome handle = None && Unix.gettimeofday () < deadline do
        Thread.delay 0.01
      done;
      check "delivery overflow returns terminal error"
        (match Run_handle.outcome handle with Some (Error _) -> true | _ -> false);
      check "overflow retains bounded event queue"
        (List.length (Run_handle.drain handle) = 1);
      Run_handle.close handle;
      let cfg = config "touch must-not-exist\n" in
      let handle =
        Run_handle.start
          ~checkpoint:(fun () -> Error "Fixture database write failed.")
          cfg ~prompt:"fixture"
      in
      let deadline = Unix.gettimeofday () +. 2. in
      while Run_handle.outcome handle = None && Unix.gettimeofday () < deadline do
        Thread.delay 0.01
      done;
      check "checkpoint refusal prevents spawn"
        (Run_handle.outcome handle = Some (Error "Fixture database write failed.")
        && not (Sys.file_exists (Filename.concat directory "must-not-exist")));
      Run_handle.close handle;
      let handle = Run_handle.start (config "sleep 10\n") ~prompt:"fixture" in
      Thread.delay 0.05;
      let before = Unix.gettimeofday () in
      Run_handle.close handle;
      check "close cancels and joins runner"
        (Unix.gettimeofday () -. before < 1. && Run_handle.outcome handle <> None);
      let cfg = config completed in
      for _ = 1 to 30 do
        ignore (ok (run cfg))
      done;
      check "repeated process runs remain usable" (ok (run cfg)).succeeded);
  Printf.printf "Passed %d process checks. Fake executables and temporary files only.\n"
    !checks
