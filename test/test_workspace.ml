open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let require label = function
  | Ok value -> value
  | Error error -> failwith (label ^ ": " ^ error)

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
          require
            ("jj fixture " ^ String.concat " " args)
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
      let reference = Workspace.reference workspace in
      let task = Model.make ~id:"task" ~title:"Work on this task" ~repository:"fixture" in
      let attached = ok (Model.attach_workspace task reference) in
      check "task attachment records source repository"
        (attached.repository = source && attached.workspace = Some reference);
      check "workspace cannot be reattached"
        (Result.is_error (Model.attach_workspace attached reference));
      let running = ok (Model.start task "run") in
      check "workspace cannot change after run start"
        (Result.is_error (Model.attach_workspace running reference));
      let snapshot : Snapshot.t =
        { tasks = [ attached ]; drafts = []; selected = "task"; serial = 200 }
      in
      let loaded = ok (Snapshot.decode (Snapshot.encode snapshot)) in
      check "workspace identity round trips"
        ((List.hd loaded.tasks).workspace = Some reference);
      let restored =
        ok (Workspace.restore (Option.get (List.hd loaded.tasks).workspace))
      in
      check "restored workspace keeps exact base"
        (Workspace.base restored = Workspace.base workspace);
      let store = ok (Storage.open_store (Filename.concat directory "tasks.sqlite")) in
      ok (Storage.save store snapshot ~events:[]);
      Storage.close store;
      let store = ok (Storage.open_store (Filename.concat directory "tasks.sqlite")) in
      let loaded = Option.get (ok (Storage.load store)) in
      Storage.close store;
      check "workspace persists in SQLite"
        ((List.hd loaded.tasks).workspace = Some reference);
      let legacy = Yojson.Basic.from_string (Snapshot.encode snapshot) in
      let rec strip = function
        | `Assoc fields ->
            `Assoc
              (List.filter_map
                 (fun (key, value) ->
                   if key = "workspace" then None else Some (key, strip value))
                 fields)
        | `List values -> `List (List.map strip values)
        | value -> value
      in
      let legacy = ok (Snapshot.decode (Yojson.Basic.to_string (strip legacy))) in
      check "legacy task without workspace loads" ((List.hd legacy.tasks).workspace = None);
      List.iter
        (fun invalid ->
          check "invalid persisted identity refused"
            (Result.is_error (Workspace.restore invalid)))
        [
          { reference with directory = "relative" };
          { reference with directory = source ^ "/nested" };
          { reference with base = "@" };
          { reference with name = "bad\nname" };
          { reference with directory = "/tmp/../task" };
        ];
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
      let output = require "plain command fixture" (command ~timeout:1. ~max_output:32) in
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
