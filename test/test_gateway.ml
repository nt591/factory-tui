open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let make url key = Gateway.make ~base_url:url ~key_environment:key in
  List.iter
    (fun url ->
      check "secure or loopback URL accepted"
        (Result.is_ok (make url "FACTORY_TEST_UNSET_KEY")))
    [
      "https://gateway.example/v1";
      "https://gateway.example:443/v1";
      "http://localhost:4000/v1";
      "http://127.0.0.1/v1";
      "http://[::1]:4000/v1";
      "https://example.com/a%20b";
    ];
  List.iter
    (fun url -> check ("unsafe URL refused: " ^ url) (Result.is_error (make url "KEY")))
    [
      "http://remote.example";
      "https://user:secret@example.com";
      "https://example.com?key=secret";
      "https://example.com#secret";
      "https://";
      "example.com";
      "file:///tmp/path";
      "https://bad host/v1";
      "https://example.com:0";
      "https://example.com:99999";
      "https://example.com:";
      "https://example.com:bad";
      "https://example.com/%zz";
      "https://user%40host.example/v1";
      "https://example.com\\evil";
      "https://-bad.example/v1";
    ];
  List.iter
    (fun key ->
      check "invalid environment reference refused"
        (Result.is_error (make "https://example.com" key)))
    [ ""; "1KEY"; "KEY=value"; "secret-value!"; "KEY\n"; String.make 257 'a' ];
  let gateway =
    ok
      (Gateway.parse
         "base_url = 'https://gateway.example/v1'\n\
          key_environment = 'FACTORY_TEST_UNSET_KEY'\n")
  in
  check "gateway getters"
    (Gateway.base_url gateway = "https://gateway.example/v1"
    && Gateway.key_environment gateway = "FACTORY_TEST_UNSET_KEY");
  List.iter
    (fun source ->
      check "invalid config refused without echo"
        (match Gateway.parse source with
        | Error error -> not (Controller.contains error "accidental-secret")
        | Ok _ -> false))
    [
      "api_key = 'accidental-secret'";
      "base_url = 'https://example.com'";
      "base_url = true\nkey_environment = 'KEY'";
      "bad = ['accidental-secret'";
      String.make 65537 ' ';
    ];
  let directory = Unix.realpath (Filename.get_temp_dir_name ()) in
  List.iter
    (fun thread_id ->
      let invocation =
        ok
          (Codex.invocation ~executable:"/fixture/codex" ~directory ~model:"model"
             ~thread_id)
      in
      let configured = Codex.with_gateway invocation gateway in
      check "provider references key name without reading it"
        (List.mem {|model_providers.factory_gateway.env_key="FACTORY_TEST_UNSET_KEY"|}
           configured.arguments);
      check "provider uses Responses wire format"
        (List.mem {|model_providers.factory_gateway.wire_api="responses"|}
           configured.arguments);
      check "provider disables OpenAI authentication requirement"
        (List.mem {|model_providers.factory_gateway.requires_openai_auth=false|}
           configured.arguments);
      check "prompt remains stdin" (List.hd (List.rev configured.arguments) = "-");
      check "resume shape remains valid"
        (match (thread_id, configured.arguments) with
        | Some _, "exec" :: "resume" :: _ -> true
        | None, "exec" :: _ -> true
        | _ -> false))
    [ None; Some "explicit-thread" ];
  let filename = Filename.temp_file "factory-gateway" ".toml" in
  Fun.protect
    ~finally:(fun () -> Sys.remove filename)
    (fun () ->
      let channel = open_out filename in
      output_string channel "base_url='http://127.0.0.1:4000/v1'\nkey_environment='KEY'";
      close_out channel;
      check "gateway config loads locally" (Result.is_ok (Gateway.load filename)));
  check "missing config fails" (Result.is_error (Gateway.load (filename ^ ".missing")));
  Printf.printf "Passed %d gateway checks. No credentials or network access.\n" !checks
