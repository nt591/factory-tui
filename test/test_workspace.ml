open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let directory = Filename.temp_file "factory-workspace" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let directory = Unix.realpath directory in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then (
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path)
    else Sys.remove path
  in
  Fun.protect
    ~finally:(fun () -> remove directory)
    (fun () ->
      let jj = "/opt/homebrew/bin/jj" in
      let source = Filename.concat directory "source" in
      Unix.mkdir source 0o700;
      let run args =
        let output =
          ok
            (Command.run ~executable:jj ~arguments:args ~directory:source ~timeout:15.
               ~max_output:2097152)
        in
        check "fixture jj succeeds" (output.status = Unix.WEXITED 0);
        output.stdout
      in
      ignore (run [ "git"; "init"; "--colocate" ]);
      let destination = Filename.concat directory "task-one" in
      let workspace = ok (Workspace.create ~jj ~source ~destination ~revision:"@") in
      check "workspace created"
        (Sys.is_directory destination
        && Sys.file_exists (Filename.concat destination ".jj"));
      check "workspace identity recorded"
        (Workspace.destination workspace = destination
        && Workspace.source workspace = source
        && Workspace.name workspace = "factory-task-one");
      let parent =
        run
          [
            "--repository";
            destination;
            "--ignore-working-copy";
            "log";
            "-r";
            "@-";
            "--no-graph";
            "-T";
            "commit_id";
          ]
      in
      check "exact parent used" (parent = Workspace.base workspace);
      check "new workspace diff empty" (ok (Workspace.diff ~jj workspace) = "");
      let file = Filename.concat destination "example.txt" in
      let channel = open_out file in
      output_string channel "new task content\n";
      close_out channel;
      let diff = ok (Workspace.diff ~jj workspace) in
      check "new file included in review"
        (Controller.contains diff "example.txt"
        && Controller.contains diff "+new task content");
      check "source files untouched"
        (not (Sys.file_exists (Filename.concat source "example.txt")));
      check "existing destination refused"
        (Result.is_error (Workspace.create ~jj ~source ~destination ~revision:"@"));
      check "nested destination refused"
        (Result.is_error
           (Workspace.create ~jj ~source
              ~destination:(Filename.concat source "nested")
              ~revision:"@"));
      check "multiple base commits refused"
        (Result.is_error
           (Workspace.create ~jj ~source
              ~destination:(Filename.concat directory "multi")
              ~revision:"all()"));
      check "option-like revision refused"
        (Result.is_error
           (Workspace.create ~jj ~source
              ~destination:(Filename.concat directory "bad")
              ~revision:"--all"));
      let other =
        ok
          (Workspace.create ~jj ~source
             ~destination:(Filename.concat directory "task-two")
             ~revision:(Workspace.base workspace))
      in
      check "tasks have distinct workspaces" (Workspace.destination other <> destination);
      check "second task files isolated"
        (not
           (Sys.file_exists (Filename.concat (Workspace.destination other) "example.txt")));
      let git_only = Filename.concat directory "git-only" in
      Unix.mkdir git_only 0o700;
      check "Git-only source not initialized silently"
        (Result.is_error
           (Workspace.create ~jj ~source:git_only
              ~destination:(Filename.concat directory "git-task")
              ~revision:"@"));
      let fixture = Filename.concat directory "command-fixture" in
      let write script =
        let channel = open_out fixture in
        output_string channel ("#!/bin/sh\n" ^ script);
        close_out channel;
        Unix.chmod fixture 0o700
      in
      let command ~timeout ~max_output =
        Command.run ~executable:fixture ~arguments:[] ~directory ~timeout ~max_output
      in
      write "printf 'stdout'; printf 'stderr' >&2\n";
      let output = ok (command ~timeout:1. ~max_output:32) in
      check "command captures output and drains stderr"
        (output.stdout = "stdout" && output.stderr_bytes = 6);
      write "printf '%0100d' 0\n";
      check "command output cap enforced"
        (Result.is_error (command ~timeout:1. ~max_output:32));
      write "sleep 10\n";
      let before = Unix.gettimeofday () in
      check "command timeout enforced"
        (Result.is_error (command ~timeout:0.1 ~max_output:32));
      check "command timeout cleanup bounded" (Unix.gettimeofday () -. before < 1.);
      check "invalid relative source refused"
        (Result.is_error
           (Workspace.create ~jj ~source:"relative"
              ~destination:(Filename.concat directory "relative-task")
              ~revision:"@")));
  Printf.printf "Passed %d workspace checks. Temporary jj repositories only.\n" !checks
