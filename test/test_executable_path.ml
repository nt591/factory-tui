open Factory_tui

let () =
  let directory = Filename.temp_file "factory-path" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let file = Filename.concat directory "fixture-tool" in
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists file then Sys.remove file;
      Unix.rmdir directory)
    (fun () ->
      let out = open_out file in
      output_string out "fixture";
      close_out out;
      assert (Executable_path.find ~path:directory "fixture-tool" = None);
      Unix.chmod file 0o700;
      assert (
        Executable_path.find ~path:("/missing:" ^ directory) "fixture-tool" = Some file);
      assert (Executable_path.find ~path:directory "missing" = None);
      assert (Executable_path.find ~path:directory "../fixture-tool" = None);
      let controller = Controller.create () in
      controller.database_path <- Some "/fixture/not-opened.sqlite";
      Controller.act controller Controller.Begin_workspace;
      let form = Option.get controller.workspace_form in
      assert (
        Workspace_form.value form Jj
        = Option.value ~default:"" (Executable_path.resolve "jj")));
  print_endline
    "Passed executable PATH discovery and new-task default checks. No executable started."
