open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let view offset : Chat_viewport.view = { offset; distance = 0; following = false }

let measure () =
  let rows =
    List.init 20000 (fun i -> Printf.sprintf "Chat row %06d: %s" i (String.make 60 'x'))
  in
  let time fn =
    let start = Unix.gettimeofday () in
    fn ();
    Unix.gettimeofday () -. start
  in
  let rounds = 20 in
  let all =
    time (fun () ->
        for _ = 1 to rounds do
          List.filteri (fun i _ -> i >= 10) rows
          |> List.map (Notty.I.string Notty.A.empty)
          |> Notty.I.vcat |> ignore
        done)
  in
  let visible =
    time (fun () ->
        for _ = 1 to rounds do
          Chat_viewport.visible_rows (view 10) ~height:30 rows
          |> List.map (Notty.I.string Notty.A.empty)
          |> Notty.I.vcat |> ignore
        done)
  in
  Printf.printf
    "Synthetic chat: 20000 rows; 20 image-building passes.\n\
     Unbounded tail images: %.3f ms\n\
     30 visible-row images: %.3f ms\n\
     Excludes wrapping, anchoring, search, and terminal output.\n"
    (all *. 1000.) (visible *. 1000.)

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else
    let rows = List.init 100 string_of_int in
    check "top selects exact visible rows"
      (Chat_viewport.visible_rows (view 0) ~height:3 rows = [ "0"; "1"; "2" ]);
    check "middle selects exact visible rows"
      (Chat_viewport.visible_rows (view 49) ~height:3 rows = [ "49"; "50"; "51" ]);
    check "final partial window retains remaining rows"
      (Chat_viewport.visible_rows (view 98) ~height:5 rows = [ "98"; "99" ]);
    check "hidden pane creates no row images"
      (Chat_viewport.visible_rows (view 0) ~height:0 rows = []);
    check "negative height selects no rows"
      (Chat_viewport.visible_rows (view 0) ~height:(-1) rows = []);
    check "negative offset clamps to top"
      (Chat_viewport.visible_rows (view (-1)) ~height:1 rows = [ "0" ]);
    check "past end selects no rows"
      (Chat_viewport.visible_rows (view max_int) ~height:3 rows = []);
    check "oversized height retains available rows"
      (Chat_viewport.visible_rows (view 0) ~height:max_int rows = rows);
    let viewport = Chat_viewport.create () in
    let anchors = List.init 100 (fun index -> ("message", index)) in
    let current =
      Chat_viewport.update viewport ~task_id:"task" ~rows:anchors ~height:5 ~distance:0
        ~seek:None
    in
    check "following uses last visible window"
      (Chat_viewport.visible_rows current ~height:5 rows
      = [ "95"; "96"; "97"; "98"; "99" ]);
    let paused =
      Chat_viewport.update viewport ~task_id:"task" ~rows:anchors ~height:5 ~distance:50
        ~seek:None
    in
    let before = Chat_viewport.visible_rows paused ~height:5 rows in
    let extended = anchors @ [ ("new", 0) ] in
    let after =
      Chat_viewport.update viewport ~task_id:"task" ~rows:extended ~height:5
        ~distance:paused.distance ~seek:None
    in
    check "bounded rows preserve paused history on append"
      (Chat_viewport.visible_rows after ~height:5 (rows @ [ "new" ]) = before);
    let calls = ref 0 in
    Chat_viewport.visible_rows paused ~height:5 rows |> List.iter (fun _ -> incr calls);
    check "only viewport capacity reaches image construction" (!calls = 5);
    let unsafe = [ "safe"; "\027unrendered control" ] in
    let image =
      Chat_viewport.visible_rows (view 0) ~height:1 unsafe
      |> List.map (Notty.I.string Notty.A.empty)
      |> Notty.I.vcat
    in
    check "hidden row cannot reach image constructor" (Notty.I.height image = 1);
    Printf.printf "Passed %d chat window checks. Pure rows only.\n" !checks
