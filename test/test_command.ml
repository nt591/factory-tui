open Factory_tui
open Scope

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok ~context = function
  | Ok value -> value
  | Error error -> failwith (context ^ ": " ^ error)

let fixture mode =
  match mode with
  | "output" ->
      print_string "stdout";
      prerr_string "stderr"
  | "oversized-output" -> print_string (String.make 100 'x')
  | "oversized-error" -> prerr_string (String.make 100 'x')
  | "burst-error" ->
      prerr_string (String.make 262144 'e');
      print_string "stdout"
  | "closed-output" ->
      Unix.close Unix.stdout;
      Unix.close Unix.stderr;
      Unix.sleep 10
  | "failure" -> exit 7
  | "wait" -> Unix.sleep 10
  | "directory" -> print_string (Sys.getcwd ())
  | "argument" -> print_string Sys.argv.(3)
  | _ -> exit 2

let tests () =
  let executable = Unix.realpath Sys.executable_name in
  let directory = Filename.temp_file "factory-command" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let directory = Unix.realpath directory in
  let@ () = on_exit (fun () -> Unix.rmdir directory) in
  let command ?(arguments = []) ?(timeout = 1.) ?(max_output = 32) mode =
    Command.run ~executable
      ~arguments:([ "--fixture"; mode ] @ arguments)
      ~directory ~timeout ~max_output
  in
  let output = ok ~context:"initial stdout/stderr" (command "output") in
  check "stdout captured and stderr counted"
    (output.stdout = "stdout" && output.stderr_bytes = 6);
  check "successful command exit retained" (output.status = Unix.WEXITED 0);
  check "stdout cap enforced"
    (command "oversized-output" = Error "Command output limit exceeded.");
  check "stderr cap enforced"
    (command "oversized-error" = Error "Command output limit exceeded.");
  let failed = ok ~context:"nonzero exit" (command "failure") in
  check "nonzero exit is data not a transport error" (failed.status = Unix.WEXITED 7);
  let started = Unix.gettimeofday () in
  check "timeout enforced"
    (command ~timeout:0.1 "wait" = Error "Command timeout exceeded.");
  check "timeout kills and reaps promptly" (Unix.gettimeofday () -. started < 1.);
  check "closed output pipes cannot hide running child from timeout"
    (command ~timeout:0.1 "closed-output" = Error "Command timeout exceeded.");
  let burst =
    ok ~context:"256 KiB stderr burst" (command ~max_output:1048576 "burst-error")
  in
  check "stderr burst drained without losing stdout"
    (burst.stdout = "stdout" && burst.stderr_bytes = 262144
   && burst.status = Unix.WEXITED 0);
  let output = ok ~context:"working directory" (command ~max_output:4096 "directory") in
  check "requested working directory used" (output.stdout = directory);
  let argument = "literal 'quotes' $(not-a-shell-command); 界" in
  let output =
    ok ~context:"literal arguments"
      (command ~max_output:4096 ~arguments:[ argument ] "argument")
  in
  check "arguments are passed without shell interpretation" (output.stdout = argument);
  check "invalid limits rejected" (Result.is_error (command ~timeout:Float.nan "output"));
  check "negative limit rejected" (Result.is_error (command ~max_output:(-1) "output"));
  check "relative executable rejected"
    (Result.is_error
       (Command.run ~executable:"relative" ~arguments:[] ~directory ~timeout:1.
          ~max_output:32));
  check "missing executable is an error"
    (Result.is_error
       (Command.run
          ~executable:(Filename.concat directory "missing")
          ~arguments:[] ~directory ~timeout:1. ~max_output:32));
  check "null-byte argument rejected"
    (Result.is_error (command ~arguments:[ "bad\000argument" ] "argument"));
  for iteration = 1 to 20 do
    let result =
      ok ~context:(Printf.sprintf "repeated output %d" iteration) (command "output")
    in
    check "repeated launches preserve pipe and exit behavior"
      (result.Command.status = Unix.WEXITED 0
      && result.stdout = "stdout" && result.stderr_bytes = 6)
  done;
  for batch = 1 to 3 do
    let results = Array.make 8 None in
    let workers =
      Array.init 8 (fun index ->
          Thread.create (fun () -> results.(index) <- Some (command "output")) ())
    in
    Array.iter Thread.join workers;
    Array.iteri
      (fun index result ->
        let name = Printf.sprintf "concurrent output batch %d worker %d" batch index in
        (match result with
        | Some (Error error) -> failwith (name ^ ": " ^ error)
        | _ -> ());
        check name
          (match result with
          | Some (Ok result) ->
              result.Command.status = Unix.WEXITED 0
              && result.stdout = "stdout" && result.stderr_bytes = 6
          | _ -> false))
      results
  done;
  check "all direct children reaped"
    (try
       ignore (Unix.waitpid [ Unix.WNOHANG ] (-1));
       false
     with Unix.Unix_error (Unix.ECHILD, _, _) -> true);
  Printf.printf
    "Passed %d native command checks. Temporary directory; no shell or agent.\n" !checks

let () =
  if Array.length Sys.argv >= 3 && Sys.argv.(1) = "--fixture" then fixture Sys.argv.(2)
  else tests ()
