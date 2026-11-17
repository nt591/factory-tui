let snapshot ~size t =
  let width, height = try Scanf.sscanf size "%dx%d%!" (fun w h -> w, h)
    with _ -> invalid_arg "Size must use COLSxROWS." in
  if width < 1 || height < 1 || width > 1000 || height > 1000 then
    invalid_arg "Snapshot dimensions must be between 1 and 1000.";
  Notty_unix.output_image (Ui.render t ~width ~height).image

let interactive ~events ~database =
  if not (Unix.isatty Unix.stdin && Unix.isatty Unix.stdout) then
    Error "Interactive mode needs a terminal. Use --snapshot for a headless preview."
  else
    let t = Controller.create ~external_events:(events <> "") () in
    t.database_path <- (if database = "" then None else Some database);
    let opened = if database = "" then Ok None else
      match Persistence.start database with
      | Error error -> Error error
      | Ok (worker, loaded) ->
          Option.iter (Controller.restore t) loaded;
          t.retain_events <- true;
          (match Persistence.submit worker (Controller.snapshot t) ~events:[] with
           | Error error -> ignore (Persistence.close worker); Error error
           | Ok () -> match Persistence.flush worker with
             | Error error -> ignore (Persistence.close worker); Error error
             | Ok () -> Ok (Some worker)) in
    match opened with
    | Error error -> Error error
    | Ok worker ->
        let final_error = ref None in
        Fun.protect ~finally:(fun () -> Option.iter (fun worker ->
          match Persistence.close worker with Ok () -> () | Error error -> final_error := Some error) worker) (fun () ->
          let source = if events = "" then None else Some (Events.open_source events) in
          Fun.protect ~finally:(fun () -> Option.iter (fun (s : Events.source) -> Unix.close s.fd) source) (fun () ->
            let term = Notty_unix.Term.create ~mouse:true () in
            let previous_term = Sys.signal Sys.sigterm (Sys.Signal_handle (fun _ -> t.quit <- true)) in
            let last_saved = ref (Controller.snapshot t) in
            let persist () = Option.iter (fun worker ->
              let current = Controller.snapshot t in
              if current <> !last_saved || t.storage_events <> [] then (
                match Persistence.submit worker current ~events:t.storage_events with
                | Ok () -> last_saved := current; t.storage_events <- []
                | Error error ->
                    t.status <- "Storage error: " ^ error;
                    if List.length t.storage_events >= 1024 then (
                      final_error := Some error; t.quit <- true));
              Option.iter (fun error -> t.status <- "Storage error: " ^ error) (Persistence.error worker)) worker in
            Fun.protect ~finally:(fun () ->
              Notty_unix.Term.release term; Sys.set_signal Sys.sigterm previous_term;
              Option.iter (fun worker ->
                let result = match Persistence.flush worker with
                  | Error error -> Error error
                  | Ok () -> Persistence.submit worker (Controller.snapshot t) ~events:t.storage_events in
                match result with Ok () -> t.storage_events <- [] | Error error -> final_error := Some error) worker) (fun () ->
              let input, _ = Notty_unix.Term.fds term in
              let pasting = ref false in
              while not t.quit do
                Controller.tick t (Unix.gettimeofday ());
                Option.iter (fun source -> List.iter (function
                  | Ok event -> Controller.receive t event
                  | Error error -> t.status <- "Replay error: " ^ error) (Events.poll source)) source;
                persist ();
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
              done)));
        match !final_error with None -> Ok () | Some error -> Error error
