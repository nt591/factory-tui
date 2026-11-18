type 'a t = { pinned : 'a list; repositories : 'a Board_window.t; cue : string }

let make ~height ~selected ~scroll ~pinned repositories =
  let capacity = max 0 (height - 2) in
  let pinned = List.filteri (fun index _ -> index < capacity) pinned in
  let remaining = max 0 (capacity - List.length pinned) in
  (* The overflow cue must not cover a repository row or its click target. *)
  let available =
    if List.length repositories > remaining && remaining > 1 then remaining - 1
    else remaining
  in
  let window = Board_window.make ~capacity:available ~selected ~scroll:0 repositories in
  let window =
    match scroll with
    | None -> window
    | Some offset ->
        let offset =
          max 0 (min offset (max 0 (List.length repositories - max 1 available)))
        in
        let items =
          List.filteri
            (fun index _ -> index >= offset && index - offset < available)
            repositories
        in
        let count = List.length items in
        {
          Board_window.items;
          offset;
          first = (if count = 0 then 0 else offset + 1);
          last = (if count = 0 then 0 else offset + count);
          total = List.length repositories;
          above = offset > 0;
          below = offset + count < List.length repositories;
        }
  in
  {
    pinned;
    repositories = window;
    cue = (if available < remaining then Board_window.cue window else "");
  }
