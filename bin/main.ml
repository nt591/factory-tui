open Factory_tui

let () =
  let snapshot = ref false and size = ref "120x36" and events = ref "" in
  Arg.parse [
    "--snapshot", Arg.Set snapshot, " Render one non-interactive demo frame";
    "--size", Arg.Set_string size, "COLSxROWS Snapshot size (default 120x36)";
    "--events", Arg.Set_string events, "PATH Read fixture JSONL from a file or FIFO instead of demo timers"
  ] (fun _ -> raise (Arg.Bad "Unexpected positional argument.")) "factory-tui [--snapshot] [--events PATH]";
  let t = Controller.create ~external_events:(!events <> "") () in
  if !snapshot then (
    let width, height = try Scanf.sscanf !size "%dx%d%!" (fun w h -> w, h)
      with _ -> prerr_endline "Size must use COLSxROWS."; exit 2 in
    if width < 1 || height < 1 || width > 1000 || height > 1000 then (
      prerr_endline "Snapshot dimensions must be between 1 and 1000."; exit 2);
    let frame = Ui.render t ~width ~height in
    Notty_unix.output_image frame.image)
  else if not (Unix.isatty Unix.stdin && Unix.isatty Unix.stdout) then (
    prerr_endline "Interactive mode needs a terminal. Use --snapshot for a headless preview."; exit 2)
  else
    let source = if !events = "" then None else Some (Events.open_source !events) in
    Fun.protect ~finally:(fun () -> Option.iter (fun (s : Events.source) -> Unix.close s.fd) source) (fun () ->
      let term = Notty_unix.Term.create ~mouse:true () in
      let previous_term = Sys.signal Sys.sigterm (Sys.Signal_handle (fun _ -> t.quit <- true)) in
      Fun.protect ~finally:(fun () ->
        Notty_unix.Term.release term; Sys.set_signal Sys.sigterm previous_term) (fun () ->
        let input, _ = Notty_unix.Term.fds term in
        let pasting = ref false in
        while not t.quit do
          Controller.tick t (Unix.gettimeofday ());
          Option.iter (fun source -> List.iter (function
            | Ok event -> Controller.receive t event
            | Error error -> t.status <- "Replay error: " ^ error) (Events.poll source)) source;
          let width, height = Notty_unix.Term.size term in
          let frame = Ui.render t ~width ~height in
          Notty_unix.Term.image term frame.image;
          let ready = Notty_unix.Term.pending term ||
            (try let fds, _, _ = Unix.select [input] [] [] 0.1 in fds <> []
             with Unix.Unix_error (Unix.EINTR, _, _) -> false) in
          if ready then match Notty_unix.Term.event term with
            | `End -> t.quit <- true
            | `Resize _ -> ()
            | `Paste `Start -> pasting := true
            | `Paste `End -> pasting := false
            | `Key key ->
                (* Pasted shortcuts must not start runs or submit messages. *)
                if !pasting then (
                  match key with
                  | (`ASCII _ | `Uchar _), _ when t.input <> Controller.Normal -> Controller.key t key
                  | _ -> ())
                else Controller.key t key
            | `Mouse mouse -> Ui.mouse t frame ~now:(Unix.gettimeofday ()) mouse
        done))
