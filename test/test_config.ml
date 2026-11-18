open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let parse = Config.parse ~base:"/config" ~home:"/home/test" in
  check "empty config preserves memory mode" ((ok (parse "")).database = None);
  check "empty config keeps automatic pane sizes"
    ((ok (parse "")).layout = Pane_layout.automatic);
  let defaults =
    (ok (parse "[layout]\nboard_width_percent=55\nboard_height_percent=40")).layout
  in
  check "layout percentages stay typed"
    (Pane_layout.board_width defaults = Some 55
    && Pane_layout.board_height defaults = Some 40);
  check "partial layout supports automatic other orientation"
    (Pane_layout.board_width (ok (parse "[layout]\nboard_height_percent=40")).layout
    = None);
  check "empty layout table remains automatic"
    ((ok (parse "[layout]")).layout = Pane_layout.automatic);
  List.iter
    (fun source ->
      check "invalid layout rejected without coercion" (Result.is_error (parse source)))
    [
      "layout=true";
      "[layout]\nboard_width_percent=9";
      "[layout]\nboard_height_percent=91";
      "[layout]\nboard_width_percent=-1";
      "[layout]\nboard_height_percent=40.0";
      "[layout]\nboard_width_percent='50'";
      "[layout]\nboard_height_percent=true";
      "[layout]\nboard_width=50";
      "[layout]\napi_key='hidden-layout-secret'";
    ];
  List.iter
    (fun percent ->
      check "inclusive layout limits accepted"
        (Result.is_ok
           (parse
              (Printf.sprintf "[layout]\nboard_width_percent=%d\nboard_height_percent=%d"
                 percent percent))))
    [ 10; 90 ];
  check "absolute database path"
    ((ok (parse "[storage]\ndatabase = '/data/board.sqlite'\n")).database
   = Some "/data/board.sqlite");
  check "relative database path"
    ((ok (parse "[storage]\ndatabase = 'board.sqlite'\n")).database
   = Some "/config/board.sqlite");
  check "home database path"
    ((ok (parse "[storage]\ndatabase = '~/board.sqlite'\n")).database
   = Some "/home/test/board.sqlite");
  List.iter
    (fun source -> check "invalid config rejected" (Result.is_error (parse source)))
    [
      "[storage]\ndatabase = 1";
      "storage = true";
      "[storage]\ndatabse = 'typo'";
      "[gateway]\napi_key = 'secret'";
      "[storage]\ndatabase = ''";
      "[storage]\ndatabase = \"bad\\u0000path\"";
      "[storage";
      "[storage]\ndatabase='a'\ndatabase='b'";
      String.make 65537 ' ';
    ];
  let settings =
    ok
      (parse
         {|[storage]
database = "board.sqlite"
[workspace]
jj = "/tools/jj"
source = "repo"
parent = "~/tasks"
revision = "main@origin"
model = "coding-small"
|})
  in
  check "workspace paths resolved relative to config and home"
    (settings.workspace.jj = Some "/tools/jj"
    && settings.workspace.source = Some "/config/repo"
    && settings.workspace.parent = Some "/home/test/tasks");
  check "workspace revision and model stay literal"
    (settings.workspace.revision = Some "main@origin"
    && settings.workspace.model = Some "coding-small");
  check "partial workspace defaults supported"
    ((ok (parse "[workspace]\njj='/tools/jj'")).workspace.source = None);
  check "empty workspace table optional"
    ((ok (parse "[workspace]\n")).workspace = Workspace_defaults.empty);
  List.iter
    (fun source ->
      check "unsafe workspace defaults rejected" (Result.is_error (parse source)))
    [
      "[workspace]\njj=1";
      "workspace=true";
      "[workspace]\nsource=''";
      "[workspace]\nparent=\"bad\\u0000path\"";
      "[workspace]\nrevision='--last'";
      "[workspace]\nmodel='-option'";
      "[workspace]\nunknown='value'";
      "[workspace]\nworkspace_write=true";
      "[workspace]\napi_key='accidental-secret'";
    ];
  check "default config path"
    (Config.default_path ~home:"/home/test" ~xdg:None
    = "/home/test/.config/factory-tui/config.toml");
  check "XDG config path"
    (Config.default_path ~home:"/home/test" ~xdg:(Some "/xdg")
    = "/xdg/factory-tui/config.toml");
  check "relative XDG ignored"
    (Config.default_path ~home:"/home/test" ~xdg:(Some "relative")
    = "/home/test/.config/factory-tui/config.toml");
  let dir = Filename.temp_file "factory-config" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o700;
  let dir = Unix.realpath dir in
  Fun.protect
    ~finally:(fun () ->
      let config_dir = Filename.concat dir "factory-tui" in
      if Sys.file_exists config_dir then (
        Array.iter
          (fun name -> Sys.remove (Filename.concat config_dir name))
          (Sys.readdir config_dir);
        Unix.rmdir config_dir);
      Unix.rmdir dir)
    (fun () ->
      let config_dir = Filename.concat dir "factory-tui" in
      Unix.mkdir config_dir 0o700;
      let filename = Filename.concat config_dir "config.toml" in
      let resolve ?config ?database ?(no_config = false) () =
        Config.resolve ~home:dir ~xdg:(Some dir) ~config ~database ~no_config
      in
      check "missing default config is optional" (ok (resolve ()) = None);
      check "missing explicit config fails"
        (Result.is_error (resolve ~config:filename ()));
      let write source =
        let channel = open_out filename in
        output_string channel source;
        close_out channel
      in
      write "[storage]\ndatabase = 'board.sqlite'";
      check "default config is discovered"
        (ok (resolve ()) = Some (Filename.concat config_dir "board.sqlite"));
      check "explicit config resolves relative path"
        (ok (resolve ~config:filename ())
        = Some (Filename.concat config_dir "board.sqlite"));
      check "CLI path overrides config"
        (ok (resolve ~database:"/override.sqlite" ()) = Some "/override.sqlite");
      check "CLI home expansion"
        (ok (resolve ~database:"~/cli.sqlite" ())
        = Some (Filename.concat dir "cli.sqlite"));
      check "no-config preserves memory" (ok (resolve ~no_config:true ()) = None);
      check "no-config permits CLI database"
        (ok (resolve ~no_config:true ~database:"/cli.sqlite" ()) = Some "/cli.sqlite");
      check "conflicting config options fail"
        (Result.is_error (resolve ~no_config:true ~config:filename ()));
      write
        "[storage]\n\
         database='board.sqlite'\n\
         [workspace]\n\
         source='repo'\n\
         parent='tasks'\n\
         jj='/tools/jj'\n\
         [layout]\n\
         board_width_percent=55\n\
         board_height_percent=40";
      let settings =
        ok
          (Config.resolve_settings ~home:dir ~xdg:(Some dir) ~config:None ~no_config:false
             ~database:(Some "/override.sqlite"))
      in
      check "CLI database override preserves workspace defaults"
        (settings.database = Some "/override.sqlite"
        && settings.workspace.source = Some (Filename.concat config_dir "repo"));
      check "CLI database override preserves layout defaults"
        (Pane_layout.board_width settings.layout = Some 55
        && Pane_layout.board_height settings.layout = Some 40);
      let ignored =
        ok
          (Config.resolve_settings ~home:dir ~xdg:(Some dir) ~config:None ~no_config:true
             ~database:None)
      in
      check "no-config bypasses layout defaults" (ignored.layout = Pane_layout.automatic);
      check "no-config bypasses workspace defaults"
        (ignored.workspace = Workspace_defaults.empty);
      check "defaults do not create source or parent"
        ((not (Sys.file_exists (Filename.concat config_dir "repo")))
        && not (Sys.file_exists (Filename.concat config_dir "tasks")));
      check "config parsing creates no database"
        (not (Sys.file_exists (Filename.concat config_dir "board.sqlite")));
      write "bad TOML = ['hidden secret'";
      let error =
        match resolve () with Error error -> error | Ok _ -> failwith "Expected error"
      in
      check "config errors omit source content"
        (not (Controller.contains error "hidden secret"));
      check "broken default fails rather than losing persistence"
        (Result.is_error (resolve ()));
      check "no-config bypasses broken default" (ok (resolve ~no_config:true ()) = None);
      check "directory config rejected"
        (Result.is_error (Config.load ~home:dir config_dir)));
  Printf.printf "Passed %d config checks. No user config accessed.\n" !checks
