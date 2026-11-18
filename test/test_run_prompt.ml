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
  let viewport = Live_confirmation.create () in
  let render task =
    let height = Live_confirmation.required_height ~viewport (Some task) ~width:88 in
    Live_confirmation.render ~viewport (Some task) ~width:88 ~height
  in
  let view = render task in
  let buffer = Buffer.create 8192 in
  Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0)
    (88, Notty.I.height view.image)
    view.image;
  let text = Buffer.contents buffer in
  check "confirmation discloses exact queued instructions separately from old title"
    (Controller.contains text "Old title"
    && Controller.contains text "Queued instructions: 2"
    && Controller.contains text "First line"
    && Controller.contains text "Second line"
    && Controller.contains text "Unicode"
    && not (Controller.contains text "DO_NOT_SEND"));
  check "fully shown queued instructions can confirm"
    (Live_confirmation.can_confirm viewport ~policy:Model.Read_only (Some task));
  let changed =
    {
      task with
      messages =
        message "old" "DO_NOT_SEND" false
        :: [ message "first" "Different instruction" true; List.nth queued 1 ];
    }
  in
  check "changed queued text cannot reuse title-only authorization"
    (not (Live_confirmation.can_confirm viewport ~policy:Model.Read_only (Some changed)));
  let changed_id =
    {
      task with
      messages =
        List.map
          (fun (m : Model.message) ->
            if m.id = "first" then { m with id = "replacement" } else m)
          task.messages;
    }
  in
  check "changed captured message ID cannot reuse authorization"
    (not
       (Live_confirmation.can_confirm viewport ~policy:Model.Read_only (Some changed_id)));
  let changed_history =
    {
      task with
      messages =
        List.map
          (fun (m : Model.message) ->
            if not m.queued then { m with text = "Other sent history" } else m)
          task.messages;
    }
  in
  check "unsubmitted history changes do not alter next-run disclosure"
    (Live_confirmation.can_confirm viewport ~policy:Model.Read_only (Some changed_history));
  let large =
    {
      task with
      messages = [ message "large" (String.make 2000 'x' ^ "QUEUED_END") true ];
    }
  in
  let initial = Live_confirmation.render ~viewport (Some large) ~width:88 ~height:13 in
  check "long instruction changes reset reviewed-row coverage" (not initial.readable);
  Live_confirmation.key viewport (`End, []);
  let bottom = Live_confirmation.render ~viewport (Some large) ~width:88 ~height:13 in
  check "jumping to queued tail cannot skip full instruction review" (not bottom.readable);
  Printf.printf "Passed %d queued prompt/disclosure checks. Pure messages/layout only.\n"
    !checks
