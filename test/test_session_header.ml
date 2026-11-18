open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  List.iter
    (fun (mode, label) ->
      let compact = Session_header.text ~width:20 ~mode ~paused:false in
      check "compact execution mode precedes app identity"
        (String.starts_with ~prefix:label compact);
      let wide = Session_header.text ~width:120 ~mode ~paused:false in
      check "wide app identity stays compatible"
        (String.starts_with ~prefix:" FACTORY / terminal" wide))
    [
      (Menu_content.Simulation, "SIMULATION");
      (Fake, "FAKE / NO MODEL");
      (Replay, "REPLAY");
      (Live Model.Read_only, "LIVE READ");
      (Live Model.Workspace_write, "LIVE WRITE");
    ];
  check "pause is still reflected in compact header"
    (Controller.contains
       (Session_header.text ~width:55 ~mode:Simulation ~paused:true)
       "[PAUSED]");
  let render controller width height =
    let frame = Ui.render controller ~width ~height in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) frame.image;
    (frame, List.hd (String.split_on_char '\n' (Buffer.contents buffer)))
  in
  List.iter
    (fun (controller, label) ->
      let saved = Controller.snapshot controller in
      List.iter
        (fun height ->
          let frame, header = render controller 20 height in
          check "tiny terminal keeps execution badge instead of navigation footer"
            (String.starts_with ~prefix:label header
            && Notty.I.height frame.image = height);
          check "header render never changes execution or saved state"
            (Controller.snapshot controller = saved && controller.live_confirmation = None))
        [ 1; 2; 3; 8; 20 ])
    [
      (Controller.create (), "SIMULATION");
      (Controller.create ~external_events:true (), "REPLAY");
      (Controller.create ~fake_harness:true (), "FAKE / NO MODEL");
    ];
  let config =
    Result.get_ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None)
  in
  List.iter
    (fun (policy, label) ->
      let controller = Controller.create () in
      controller.database_path <- Some "/fixture/db";
      Result.get_ok
        (Controller.initialize_board controller ~saved:None
           ~live:(Some (Live_runner.with_policy config policy)));
      let saved = Controller.snapshot controller in
      List.iter
        (fun height ->
          let frame, header = render controller 20 height in
          check "compact live badge preserves requested policy"
            (String.starts_with ~prefix:label header
            && Notty.I.height frame.image = height);
          check "badge rendering cannot authorize execution"
            (Controller.snapshot controller = saved && controller.live_confirmation = None))
        [ 1; 2; 3; 8; 20 ])
    [ (Model.Read_only, "LIVE READ"); (Model.Workspace_write, "LIVE WRITE") ];
  Printf.printf "Passed %d session-header checks. Pure copy/rendering only.\n" !checks
