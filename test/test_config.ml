open Factory_tui
let checks = ref 0
let check name condition = incr checks; if not condition then failwith name
let ok = function Ok value -> value | Error error -> failwith error
let () =
  let parse = Config.parse ~base:"/config" ~home:"/home/test" in
  check "empty config preserves memory mode" ((ok (parse "")).database = None);
  check "absolute database path" ((ok (parse "[storage]\ndatabase = '/data/board.sqlite'\n")).database = Some "/data/board.sqlite");
  check "relative database path" ((ok (parse "[storage]\ndatabase = 'board.sqlite'\n")).database = Some "/config/board.sqlite");
  check "home database path" ((ok (parse "[storage]\ndatabase = '~/board.sqlite'\n")).database = Some "/home/test/board.sqlite");
  List.iter (fun source -> check "invalid config rejected" (Result.is_error (parse source)))
    ["[storage]\ndatabase = 1"; "storage = true"; "[storage]\ndatabse = 'typo'";
     "[gateway]\napi_key = 'secret'"; "[storage]\ndatabase = ''";
     "[storage]\ndatabase = \"bad\\u0000path\""; "[storage";
     "[storage]\ndatabase='a'\ndatabase='b'"; String.make 65537 ' '];
  check "default config path" (Config.default_path ~home:"/home/test" ~xdg:None = "/home/test/.config/factory-tui/config.toml");
  check "XDG config path" (Config.default_path ~home:"/home/test" ~xdg:(Some "/xdg") = "/xdg/factory-tui/config.toml");
  check "relative XDG ignored" (Config.default_path ~home:"/home/test" ~xdg:(Some "relative") = "/home/test/.config/factory-tui/config.toml");
  let dir = Filename.temp_file "factory-config" "" in
  Sys.remove dir; Unix.mkdir dir 0o700;
  let dir = Unix.realpath dir in
  Fun.protect ~finally:(fun () ->
    let config_dir = Filename.concat dir "factory-tui" in
    if Sys.file_exists config_dir then (
      Array.iter (fun name -> Sys.remove (Filename.concat config_dir name)) (Sys.readdir config_dir);
      Unix.rmdir config_dir);
    Unix.rmdir dir) (fun () ->
      let config_dir = Filename.concat dir "factory-tui" in Unix.mkdir config_dir 0o700;
      let filename = Filename.concat config_dir "config.toml" in
      let resolve ?config ?database ?(no_config=false) () = Config.resolve ~home:dir ~xdg:(Some dir) ~config ~database ~no_config in
      check "missing default config is optional" (ok (resolve ()) = None);
      check "missing explicit config fails" (Result.is_error (resolve ~config:filename ()));
      let write source = let channel = open_out filename in output_string channel source; close_out channel in
      write "[storage]\ndatabase = 'board.sqlite'";
      check "default config is discovered" (ok (resolve ()) = Some (Filename.concat config_dir "board.sqlite"));
      check "explicit config resolves relative path" (ok (resolve ~config:filename ()) = Some (Filename.concat config_dir "board.sqlite"));
      check "CLI path overrides config" (ok (resolve ~database:"/override.sqlite" ()) = Some "/override.sqlite");
      check "CLI home expansion" (ok (resolve ~database:"~/cli.sqlite" ()) = Some (Filename.concat dir "cli.sqlite"));
      check "no-config preserves memory" (ok (resolve ~no_config:true ()) = None);
      check "no-config permits CLI database" (ok (resolve ~no_config:true ~database:"/cli.sqlite" ()) = Some "/cli.sqlite");
      check "conflicting config options fail" (Result.is_error (resolve ~no_config:true ~config:filename ()));
      check "config parsing creates no database" (not (Sys.file_exists (Filename.concat config_dir "board.sqlite")));
      write "bad TOML = ['hidden secret'";
      let error = match resolve () with Error error -> error | Ok _ -> failwith "Expected error" in
      check "config errors omit source content" (not (Controller.contains error "hidden secret"));
      check "broken default fails rather than losing persistence" (Result.is_error (resolve ()));
      check "no-config bypasses broken default" (ok (resolve ~no_config:true ()) = None);
      check "directory config rejected" (Result.is_error (Config.load ~home:dir config_dir)));
  Printf.printf "Passed %d config checks. No user config accessed.\n" !checks
