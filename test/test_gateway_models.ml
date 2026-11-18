open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let calls = ref [] in
  let source =
    "base_url_environment='LITELLM_BASE_URL'\nkey_environment='LITELLM_API_KEY'"
  in
  let gateway =
    ok
      (Gateway.parse_environment
         ~lookup:(fun name ->
           calls := name :: !calls;
           Some "https://fixture.example/v1/")
         source)
  in
  check "setup resolves URL without looking up API key" (!calls = [ "LITELLM_BASE_URL" ]);
  check "trailing slash gets one model endpoint suffix"
    (Gateway_models.url gateway = "https://fixture.example/v1/models");
  check "missing URL reference is diagnosed without key lookup"
    (Result.is_error (Gateway.parse_environment ~lookup:(fun _ -> None) source));
  check "literal setup does not read environment"
    (Result.is_ok
       (Gateway.parse_environment
          ~lookup:(fun _ -> failwith "unexpected environment read")
          "base_url='https://fixture.example/v1'\nkey_environment='KEY'"));
  List.iter
    (fun source ->
      check "ambiguous or invalid reference refused"
        (Result.is_error
           (Gateway.parse_environment
              ~lookup:(fun _ -> Some "https://fixture.example")
              source)))
    [
      "base_url='https://fixture.example'\n\
       base_url_environment='URL'\n\
       key_environment='KEY'";
      "base_url_environment='BAD=NAME'\nkey_environment='KEY'";
      "base_url_environment='URL'\nsecret='bad'";
    ];
  check "model IDs are sorted and deduplicated"
    (Gateway_models.decode {|{"data":[{"id":"z"},{"id":"provider/model"},{"id":"z"}]}|}
    = Ok [ "provider/model"; "z" ]);
  let oversized =
    Yojson.Basic.to_string
      (`Assoc
         [
           ("data", `List (List.init 10001 (fun _ -> `Assoc [ ("id", `String "model") ])));
         ])
  in
  check "catalogue entry cap enforced before deduplication"
    (Result.is_error (Gateway_models.decode oversized));
  check "empty catalogue is valid" (Gateway_models.decode {|{"data":[]}|} = Ok []);
  List.iter
    (fun body ->
      check "invalid catalogue withheld" (Result.is_error (Gateway_models.decode body)))
    [
      "not-json";
      "[]";
      {|{"data":{}}|};
      {|{"data":[{"id":42}]}|};
      {|{"data":[{"id":""}]}|};
      {|{"data":[{"id":"-model"}]}|};
      {|{"data":[{"id":"injected\ntext"}]}|};
      {|{"data":[{"id":"with space"}]}|};
      String.make 1048577 'x';
    ];
  List.iter
    (fun key ->
      check "invalid or missing key prevents transport spawn"
        (Result.is_error
           (Gateway_models.fetch ~curl:"/must-not-run" ~lookup:(fun _ -> key) gateway)))
    [ None; Some ""; Some "bad\nheader"; Some (String.make 4097 'x') ];
  Printf.printf
    "Passed %d gateway catalogue checks. Pure fixture data; no credentials or network.\n"
    !checks
