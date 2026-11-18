open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let message id text queued : Model.message = { id; author = "You"; text; queued }

let () =
  let queued =
    [
      message "first" "First line\nSecond line" true; message "second" "Unicode é 👩🏽‍💻" true;
    ]
  in
  let task =
    {
      (Model.make ~id:"prompt" ~title:"Old title" ~repository:"fixture") with
      messages =
        (message "old" "DO_NOT_SEND" false :: queued)
        @ [ message "later" "history" false ];
    }
  in
  check "queued selection excludes sent history and keeps chronology"
    (Run_prompt.queued task = queued);
  let expected = "First line\nSecond line\n\nUnicode é 👩🏽‍💻" in
  check "prompt assembly retains exact newlines and Unicode"
    (Run_prompt.text queued = expected);
  check "byte length matches exact assembled prompt"
    (Run_prompt.byte_length queued = String.length expected);
  check "empty prompt has no synthetic separators"
    (Run_prompt.text [] = "" && Run_prompt.byte_length [] = 0);
  let submitted = Run_prompt.submitted task [ "second"; "first"; "first"; "missing" ] in
  check "submitted selection follows transcript order, not ID-list order"
    (submitted = queued);
  check "captured prompt excludes later queued replies"
    (Run_prompt.text
       (Run_prompt.submitted
          { task with messages = task.messages @ [ message "new" "Later reply" true ] }
          [ "first"; "second" ])
    = expected);
  check "validated capture assembles exact text"
    (Run_prompt.captured_text task [ "second"; "first" ] = Ok expected);
  List.iter
    (fun ids ->
      check "missing duplicate or empty captures fail instead of sending partial text"
        (Result.is_error (Run_prompt.captured_text task ids)))
    [ []; [ "first"; "missing" ]; [ "first"; "first" ] ];
  let duplicate = { task with messages = task.messages @ [ List.hd queued ] } in
  check "ambiguous message record cannot enter captured prompt"
    (Result.is_error (Run_prompt.captured_text duplicate [ "first"; "second" ]));
  let acknowledged =
    {
      task with
      messages =
        List.map
          (fun (message : Model.message) -> { message with queued = false })
          task.messages;
    }
  in
  check "validated capture does not depend on queued flags"
    (Run_prompt.captured_text acknowledged [ "first"; "second" ] = Ok expected);
  check "duplicate reply IDs are refused before persistence"
    (Result.is_error (Model.send task ~id:"first" "Different reply"));
  List.iter
    (fun id ->
      check "invalid reply ID length refused"
        (Result.is_error (Model.send task ~id "Reply")))
    [ ""; String.make 1025 'i' ];
  check "fresh reply retains original message chronology"
    (match Model.send task ~id:"fresh" "New reply" with
    | Error _ -> false
    | Ok sent ->
        List.map (fun (message : Model.message) -> message.id) sent.messages
        = List.map (fun (message : Model.message) -> message.id) task.messages
          @ [ "fresh" ]);
  Printf.printf "Passed %d queued prompt/disclosure checks. Pure messages/layout only.\n"
    !checks
