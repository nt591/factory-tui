open Factory_tui

let check name condition = if not condition then failwith name

let task =
  Some
    {
      (Model.make ~id:"cached-confirmation"
         ~title:(String.make 60000 'x' ^ "TITLE_END")
         ~repository:"fixture")
      with
      thread_id = Some "THREAD_END";
    }

let measure () =
  let viewport = Live_confirmation.create () in
  let frame ?viewport () =
    ignore (Live_confirmation.required_height ?viewport task ~width:88);
    ignore (Live_confirmation.render ?viewport task ~width:88 ~height:20)
  in
  let run operation =
    Gc.full_major ();
    let bytes = Gc.allocated_bytes () and time = Unix.gettimeofday () in
    for _ = 1 to 20 do
      operation ()
    done;
    (Unix.gettimeofday () -. time, Gc.allocated_bytes () -. bytes)
  in
  frame ~viewport ();
  let cached_time, cached_bytes = run (frame ~viewport) in
  let uncached_time, uncached_bytes = run frame in
  Printf.printf
    "20 confirmation height/render frames, 60-KiB title:\n\
     Cached: %.2f ms, %.0f bytes allocated\n\
     Uncached: %.2f ms, %.0f bytes allocated\n\
     Includes image construction; excludes full UI, terminal output and process work.\n"
    (cached_time *. 1000.) cached_bytes (uncached_time *. 1000.) uncached_bytes

let () =
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--measure" then measure ()
  else
    let viewport = Live_confirmation.create () in
    let required = Live_confirmation.required_height ~viewport task ~width:88 in
    let cached = Live_confirmation.render ~viewport task ~width:88 ~height:20 in
    let uncached = Live_confirmation.render task ~width:88 ~height:20 in
    check "shared preparation produces identical initial view" (cached = uncached);
    check "height preparation cannot authorize a run"
      (not (Live_confirmation.can_confirm viewport ~policy:Model.Read_only task));
    ignore (Live_confirmation.required_height ~viewport task ~width:88);
    Live_confirmation.key viewport (`End, []);
    let bottom = Live_confirmation.render ~viewport task ~width:88 ~height:20 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (88, 20) bottom.image;
    check "cache exposes final thread detail while preserving skipped-row lock"
      (Controller.contains (Buffer.contents buffer) "THREAD_END" && not bottom.readable);
    check "repeated preparation preserves scroll image"
      (let height = Live_confirmation.required_height ~viewport task ~width:88 in
       height = required
       && Live_confirmation.render ~viewport task ~width:88 ~height:20 = bottom);
    let changed = Some { (Option.get task) with title = "Short replacement" } in
    let changed_height = Live_confirmation.required_height ~viewport changed ~width:88 in
    let changed_view =
      Live_confirmation.render ~viewport changed ~width:88 ~height:changed_height
    in
    check "changed disclosure replaces retained rows"
      (changed_view = Live_confirmation.render changed ~width:88 ~height:changed_height
      && changed_height < required);
    check "cached render authorizes only current shown identity"
      (Live_confirmation.can_confirm viewport ~policy:Model.Read_only changed
      && not (Live_confirmation.can_confirm viewport ~policy:Model.Read_only task));
    check "changed policy is never authorized from stale cache"
      (not (Live_confirmation.can_confirm viewport ~policy:Model.Workspace_write changed));
    ignore (Live_confirmation.required_height ~viewport task ~width:70);
    let narrow = Live_confirmation.render ~viewport task ~width:70 ~height:20 in
    check "width change rebuilds identical rows and resets coverage"
      (narrow = Live_confirmation.render task ~width:70 ~height:20 && not narrow.readable);
    Live_confirmation.reset viewport;
    check "reset releases prior authorization"
      (not (Live_confirmation.can_confirm viewport ~policy:Model.Read_only task));
    let reset = Live_confirmation.render ~viewport task ~width:88 ~height:20 in
    check "new dialog starts at first page" (reset = cached);
    let missing = Live_confirmation.render ~viewport None ~width:88 ~height:20 in
    check "missing task discards reusable identity and cannot run"
      ((not missing.readable)
      && not (Live_confirmation.can_confirm viewport ~policy:Model.Read_only None));
    Printf.printf
      "Passed confirmation preparation/invalidation checks. Pure disclosure/layout only.\n"
