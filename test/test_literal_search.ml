open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let reference text query =
  let text = String.lowercase_ascii text and query = String.lowercase_ascii query in
  let rec scan index =
    index + String.length query <= String.length text
    && (String.sub text index (String.length query) = query || scan (index + 1))
  in
  scan 0

let measure () =
  let text = String.make 300000 'a' ^ "b" in
  let query = String.make 255 'a' ^ "b" in
  let search = Literal_search.prepare query in
  let run fn =
    Gc.full_major ();
    let bytes = Gc.allocated_bytes () and started = Unix.gettimeofday () in
    for _ = 1 to 10 do
      ignore (fn ())
    done;
    ((Unix.gettimeofday () -. started) *. 1000., Gc.allocated_bytes () -. bytes)
  in
  let fast_time, fast_bytes = run (fun () -> Literal_search.contains search text) in
  let old_time, old_bytes = run (fun () -> reference text query) in
  Printf.printf
    "Ten repeated-prefix searches, 300,001-byte text / 256-byte query:\n\
     Prepared matcher: %.2f ms, %.0f allocated bytes\n\
     Previous substring scan: %.2f ms, %.0f allocated bytes\n\
     Scoped matching only, not whole-UI performance.\n"
    fast_time fast_bytes old_time old_bytes

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else (
    List.iter
      (fun (text, query) ->
        check "literal case folding matches reference"
          (Literal_search.contains (Literal_search.prepare query) text
          = reference text query))
      [
        ("", "");
        ("", "x");
        ("abc", "");
        ("AbCd", "bc");
        ("ab", "abc");
        ("a.b[0]", ".b[");
        ("中文 é", "文");
        ("É", "é");
        ("\255A\128", "a\128");
        ("ababababac", "ababac");
        ("aaaaaaaab", "aaaab");
      ];
    let random = Random.State.make [| 19; 42 |] in
    for _ = 1 to 3000 do
      let text =
        String.init (Random.State.int random 128) (fun _ ->
            Char.chr (Random.State.int random 256))
      in
      let query =
        if text <> "" && Random.State.bool random then
          let start = Random.State.int random (String.length text) in
          String.sub text start (Random.State.int random (String.length text - start + 1))
        else
          String.init (Random.State.int random 32) (fun _ ->
              Char.chr (Random.State.int random 256))
      in
      let search = Literal_search.prepare query in
      check "random literal byte search matches previous semantics"
        (Literal_search.contains search text = reference text query);
      ignore (Literal_search.contains search "unrelated repeated-prefix aaab");
      check "prepared matcher is reusable without mutable match state"
        (Literal_search.contains search text = reference text query)
    done;
    let text = String.make 1048576 'a' ^ "END" in
    let query = String.make 255 'a' ^ "END" in
    let search = Literal_search.prepare query in
    check "large repeated prefixes find complete suffix"
      (Literal_search.contains search text);
    check "large repeated prefixes reject absent suffix"
      (not
         (Literal_search.contains
            (Literal_search.prepare (String.make 255 'a' ^ "MISS"))
            text));
    let controller = Controller.create ~external_events:true () in
    let task =
      Model.make ~id:"match" ~title:"Literal [TASK].title" ~repository:"/Repo/Fixture"
    in
    controller.tasks <- [ task ];
    controller.selected <- task.id;
    controller.query <- "[task].";
    check "board retains literal ASCII-insensitive filter"
      (Controller.visible controller = [ task ]);
    controller.query <- "[task].*";
    check "board does not treat pattern metacharacters as regex"
      (Controller.visible controller = []);
    let chat = Chat_search.create () in
    let messages =
      [
        {
          Model.id = "one";
          author = "FixtureAUTHOR";
          text = "line [literal].text";
          queued = false;
        };
      ]
    in
    Chat_search.set_query chat "[LITERAL].";
    Chat_search.sync chat messages;
    check "chat text literal search remains unchanged" (Chat_search.position chat = (1, 1));
    Chat_search.set_query chat "fixtureauthor";
    Chat_search.sync chat messages;
    check "chat author shares matching policy" (Chat_search.current chat = Some "one");
    Chat_search.clear chat;
    Chat_search.sync chat messages;
    check "clear leaves chat without matches" (Chat_search.position chat = (0, 0));
    Printf.printf
      "Passed %d literal-search checks. Pure bytes and task/search state only.\n" !checks)
