open Factory_tui
open Yojson.Basic.Util

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let parse text =
  match Config.parse ~base:"/fixture" ~home:"/fixture/home" text with
  | Ok settings -> settings
  | Error error -> failwith error

let () =
  let settings =
    parse
      "[storage]\n\
       database='board.sqlite'\n\
       [workspace]\n\
       jj='bin/jj'\n\
       source='source'\n\
       parent='~/tasks'\n\
       revision='main@origin'\n\
       model='fixture-model'\n\
       [layout]\n\
       board_width_percent=55\n\
       board_height_percent=40"
  in
  let json = Config_preview.describe settings in
  let storage = member "storage" json and workspace = member "workspace" json in
  check "preview reflects resolved database"
    (member "database" storage = `String "/fixture/board.sqlite");
  check "preview reflects resolved workspace paths"
    (member "jj" workspace = `String "/fixture/bin/jj"
    && member "source" workspace = `String "/fixture/source"
    && member "parent" workspace = `String "/fixture/home/tasks");
  check "preview retains next-run defaults"
    (member "revision" workspace = `String "main@origin"
    && member "model" workspace = `String "fixture-model");
  check "preview retains layout preferences"
    (member "board_width_percent" (member "layout" json) = `Int 55
    && member "board_height_percent" (member "layout" json) = `Int 40);
  List.iter
    (fun field ->
      check "preview discloses setup-only scope" (member field json = `Bool false))
    [
      "opens_database";
      "starts_process";
      "checks_path_existence";
      "checks_gateway_compatibility";
    ];
  check "preview is stable JSON without changing settings"
    (Yojson.Basic.from_string (Yojson.Basic.to_string json) = json
    && Config_preview.describe settings = json);
  let empty = Config_preview.describe (parse "") in
  check "memory-only config uses explicit null defaults"
    (member "database" (member "storage" empty) = `Null
    && List.for_all
         (fun (_, value) -> value = `Null)
         (to_assoc (member "workspace" empty))
    && List.for_all (fun (_, value) -> value = `Null) (to_assoc (member "layout" empty)));
  Printf.printf "Passed %d config-preview checks. Pure validated settings only.\n" !checks
