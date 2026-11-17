open Factory_tui

let check name condition = if not condition then failwith name
let ok = function Ok value -> value | Error error -> failwith error

let () =
  let directory = Unix.realpath (Filename.get_temp_dir_name ()) in
  let build ?(thread_id = None) model =
    Codex.invocation ~executable:"/fixture/codex" ~directory ~model ~thread_id
  in
  let config = ok (build "coding-large") in
  let pair a b =
    let rec loop = function
      | x :: y :: _ when x = a && y = b -> true
      | _ :: rest -> loop rest
      | [] -> false
    in
    loop config.arguments
  in
  check "new invocation uses exec" (List.hd config.arguments = "exec");
  check "JSONL requested" (List.mem "--json" config.arguments);
  check "user config ignored" (List.mem "--ignore-user-config" config.arguments);
  check "sandbox explicitly read-only" (pair "-c" {|sandbox_mode="read-only"|});
  check "approval policy explicit" (pair "-c" {|approval_policy="never"|});
  check "model stays a separate argument" (pair "--model" "coding-large");
  check "prompt read through stdin" (List.hd (List.rev config.arguments) = "-");
  check "no bypass flags"
    (List.for_all
       (fun arg -> not (Controller.contains arg "dangerously"))
       config.arguments);
  let resumed = ok (build ~thread_id:(Some "explicit-thread") "coding-large") in
  check "resume selects exact thread"
    ((match resumed.arguments with "exec" :: "resume" :: _ -> true | _ -> false)
    && List.mem "explicit-thread" resumed.arguments
    && not (List.mem "--last" resumed.arguments));
  check "resume uses process working directory"
    (resumed.directory = directory && not (List.mem "--cd" resumed.arguments));
  List.iter
    (fun model -> check "invalid model refused" (Result.is_error (build model)))
    [ ""; "-flag"; " bad"; "bad\nvalue"; String.make 257 'x' ];
  List.iter
    (fun id ->
      check "invalid resume refused"
        (Result.is_error (build ~thread_id:(Some id) "model")))
    [ ""; "--last"; "bad\nthread" ];
  check "relative directory refused"
    (Result.is_error
       (Codex.invocation ~executable:"/fixture/codex" ~directory:"relative" ~model:"model"
          ~thread_id:None));
  check "relative executable refused"
    (Result.is_error
       (Codex.invocation ~executable:"codex" ~directory ~model:"model" ~thread_id:None));
  Printf.printf "Passed Codex invocation checks. No executable started.\n"
