open Factory_tui

let messages =
  List.init 2000 (fun index ->
      {
        Model.id = string_of_int index;
        author = "Codex";
        text = String.make 120 'x' ^ " needle";
        queued = false;
      })

let () =
  let search = Chat_search.create () in
  Chat_search.set_query search "needle";
  Chat_search.sync search messages;
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then
    let time fn =
      let started = Unix.gettimeofday () in
      fn ();
      (Unix.gettimeofday () -. started) *. 1000.
    in
    let rebuilt =
      time (fun () ->
          for _ = 1 to 20 do
            Chat_search.clear search;
            Chat_search.set_query search "needle";
            Chat_search.sync search messages
          done)
    in
    let reused =
      time (fun () ->
          for _ = 1 to 20 do
            Chat_search.sync search messages;
            for row = 0 to 29 do
              ignore (Chat_search.matches search (string_of_int row))
            done
          done)
    in
    Printf.printf
      "Synthetic search: 2000 matching messages, 20 passes.\n\
       Forced match rebuilds: %.3f ms\n\
       Cached sync + 30 highlight lookups: %.6f ms\n\
       Excludes layout, viewport and terminal output.\n"
      rebuilt reused
  else (
    Chat_search.move search ~backwards:true;
    let position = Chat_search.position search in
    ignore (Chat_search.seek search);
    for _ = 1 to 20 do
      Chat_search.sync search messages
    done;
    assert (Chat_search.position search = position);
    assert (Chat_search.seek search = None);
    assert (Chat_search.matches search "1999");
    let updated =
      List.map
        (fun (message : Model.message) ->
          if message.id = "1999" then { message with text = "replacement" } else message)
        messages
    in
    Chat_search.sync search updated;
    assert (not (Chat_search.matches search "1999"));
    assert (Chat_search.position search = (1, 1999));
    Printf.printf "Passed large-search cache lifecycle checks. Pure messages only.\n")
