open Factory_tui.Scope

exception Body_error
exception Cleanup_error

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let steps = ref [] in
  let record step = steps := !steps @ [ step ] in
  let result =
    let@ () = on_exit (fun () -> record "outer cleanup") in
    record "outer body";
    let@ () = on_exit (fun () -> record "inner cleanup") in
    record "inner body";
    42
  in
  check "scope retains result" (result = 42);
  check "nested cleanup order"
    (!steps = [ "outer body"; "inner body"; "inner cleanup"; "outer cleanup" ]);
  steps := [];
  let raised =
    try
      let@ () = on_exit (fun () -> record "cleanup") in
      raise Body_error
    with Body_error -> true
  in
  check "body exception retained" raised;
  check "cleanup runs on body exception" (!steps = [ "cleanup" ]);
  let raised =
    try
      let@ () = on_exit (fun () -> raise Cleanup_error) in
      ();
      false
    with Fun.Finally_raised Cleanup_error -> true
  in
  check "cleanup exception matches Fun.protect" raised;
  steps := [];
  let raised =
    try
      let@ () = on_exit (fun () -> record "outer cleanup") in
      let@ () = on_exit (fun () -> raise Cleanup_error) in
      raise Body_error
    with Fun.Finally_raised Cleanup_error -> true
  in
  check "cleanup failure precedence retained" raised;
  check "outer cleanup runs after inner cleanup failure" (!steps = [ "outer cleanup" ]);
  let acquired = ref 0 in
  let with_value body =
    incr acquired;
    body 7
  in
  let value =
    let@ value = with_value in
    value * 2
  in
  check "binding executes scope once" (value = 14 && !acquired = 1);
  Printf.printf "Passed %d resource scope checks.\n" !checks
