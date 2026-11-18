open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let message index : Model.message =
  {
    id = Printf.sprintf "match-%05d" index;
    author = "fixture";
    text = "matching needle";
    queued = false;
  }

let () =
  let messages = List.init 20000 message in
  let search = Chat_search.create () in
  Chat_search.set_query search "needle";
  Chat_search.sync search messages;
  check "large result set starts at first message"
    (Chat_search.position search = (1, 20000));
  ignore (Chat_search.seek search);
  for index = 1 to 20000 do
    Chat_search.move search ~backwards:false;
    let expected = index mod 20000 in
    check "forward navigation preserves full chronological result order"
      (Chat_search.position search = (expected + 1, 20000)
      && Chat_search.current search = Some (message expected).id);
    check "each move creates only one pending seek"
      (Chat_search.seek search = Some (message expected).id
      && Chat_search.seek search = None)
  done;
  Chat_search.move search ~backwards:true;
  check "backward boundary wraps to last message"
    (Chat_search.position search = (20000, 20000));
  let last_id = Chat_search.current search in
  ignore (Chat_search.seek search);
  let reordered = List.rev messages in
  Chat_search.sync search reordered;
  check "result reorder retains selected ID with new ordinal"
    (Chat_search.current search = last_id
    && Chat_search.position search = (1, 20000)
    && Chat_search.seek search = None);
  Chat_search.move search ~backwards:false;
  check "navigation follows reordered current result set"
    (Chat_search.current search = Some (message 19998).id
    && Chat_search.position search = (2, 20000));
  ignore (Chat_search.seek search);
  let updated =
    List.map
      (fun (m : Model.message) ->
        if m.id = (message 19998).id then { m with text = "no match" } else m)
      reordered
  in
  Chat_search.sync search updated;
  check "removed selected match chooses first surviving result"
    (Chat_search.current search = last_id
    && Chat_search.position search = (1, 19999)
    && Chat_search.seek search = last_id);
  check "removed identity leaves membership index"
    (not (Chat_search.matches search (message 19998).id));
  let single = [ message 42 ] in
  Chat_search.sync search single;
  check "replacement list drops old index entries"
    (Chat_search.position search = (1, 1)
    && Chat_search.matches search (message 42).id
    && not (Chat_search.matches search (message 19999).id));
  ignore (Chat_search.seek search);
  Chat_search.move search ~backwards:true;
  check "single-result backward navigation is safe" (Chat_search.position search = (1, 1));
  Chat_search.clear search;
  check "clear drops count ordinal and membership"
    (Chat_search.position search = (0, 0)
    && Chat_search.current search = None
    && not (Chat_search.matches search (message 42).id));
  Chat_search.move search ~backwards:false;
  check "empty-result navigation has no pending seek" (Chat_search.seek search = None);
  Printf.printf
    "Passed %d indexed search-navigation checks. Pure message/query state only.\n" !checks
