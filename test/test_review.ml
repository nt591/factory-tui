open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let await review =
  let deadline = Unix.gettimeofday () +. 5. in
  while Review.state review = Changes.Loading && Unix.gettimeofday () < deadline do
    Review.poll review;
    Thread.delay 0.01
  done;
  check "review refresh finishes" (Review.state review <> Changes.Loading)

let () =
  let controller = Controller.create ~external_events:true () in
  Controller.act controller Controller.Open_review;
  check "demo review refuses invented diff"
    (controller.review = None && Controller.contains controller.status "no workspace");
  let directory = Filename.temp_file "factory-review" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let directory = Unix.realpath directory in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then (
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path)
    else Sys.remove path
  in
  Scope.on_exit
    (fun () -> remove directory)
    (fun () ->
      let source = Filename.concat directory "source" in
      Unix.mkdir source 0o700;
      let jj = "/opt/homebrew/bin/jj" in
      let output =
        ok
          (Command.run ~executable:jj
             ~arguments:[ "git"; "init"; "--colocate" ]
             ~directory:source ~timeout:15. ~max_output:2097152)
      in
      check "temporary jj source initialized" (output.status = Unix.WEXITED 0);
      let workspace =
        ok
          (Workspace.create ~jj ~source
             ~destination:(Filename.concat directory "task")
             ~revision:"@")
      in
      let task =
        ok
          (Model.attach_workspace
             (Model.make ~id:"review-task" ~title:"Review feature" ~repository:source)
             (Workspace.reference workspace))
      in
      let review = ok (Review.create task ~jj:"") in
      check "review binds original task identity"
        (Review.task_id review = task.id && Review.title review = task.title);
      check "open does not run jj automatically"
        (Review.state review = Changes.Idle
        && Review.editing review
        && Review.document review = None);
      Review.key review (`Enter, []);
      check "invalid path does not spawn"
        (Review.state review = Changes.Idle && Review.status review <> None);
      String.iter (fun char -> Review.key review (`ASCII char, [])) jj;
      Review.paste_key review (`Enter, []);
      check "paste cannot start refresh" (Review.state review = Changes.Idle);
      Review.key review (`Enter, []);
      await review;
      check "empty workspace has real empty patch" (Review.state review = Changes.Patch "");
      let empty_view = Review_view.render review ~width:120 ~height:36 in
      check "empty review has no file buttons"
        (List.for_all
           (fun (hit : Review_view.hit) ->
             hit.action <> Review_view.Next_file
             && hit.action <> Review_view.Previous_file)
           empty_view.hits);
      check "refresh leaves editing mode" (not (Review.editing review));
      let channel =
        open_out (Filename.concat (Workspace.destination workspace) "changed.txt")
      in
      output_string channel "a real addition\n";
      close_out channel;
      Review.refresh review;
      check "refresh is background state" (Review.state review = Changes.Loading);
      Review.refresh review;
      check "duplicate refresh bounded" (Review.status review <> None);
      await review;
      check "real new file appears in patch"
        (match Review.state review with
        | Changes.Patch patch ->
            Controller.contains patch "changed.txt"
            && Controller.contains patch "+a real addition"
        | _ -> false);
      let single_view = Review_view.render review ~width:120 ~height:36 in
      check "single-file review has no redundant file buttons"
        (List.for_all
           (fun (hit : Review_view.hit) ->
             hit.action <> Review_view.Next_file
             && hit.action <> Review_view.Previous_file)
           single_view.hits);
      check "review does not write source file"
        (not (Sys.file_exists (Filename.concat source "changed.txt")));
      List.iter
        (fun (width, height) ->
          let view = Review_view.render review ~width ~height in
          check "review frame exact size"
            (Notty.I.width view.image = width && Notty.I.height view.image = height);
          List.iter
            (fun (hit : Review_view.hit) ->
              check "review hit bounds"
                (hit.x >= 0 && hit.y >= 0 && hit.x + hit.width <= width && hit.y < height))
            view.hits)
        [ (1, 1); (20, 8); (60, 20); (120, 36) ];
      Review.key review (`ASCII 'G', []);
      ignore (Review_view.render review ~width:60 ~height:8);
      check "scroll clamps to patch" (Review.scroll review < 1000000);
      Review.key review (`ASCII 'g', []);
      check "g returns to top" (Review.scroll review = 0);
      let content = "+" ^ String.make 150 'x' ^ "界éLONG_LINE_END" in
      let channel =
        open_out (Filename.concat (Workspace.destination workspace) "long.txt")
      in
      output_string channel (String.sub content 1 (String.length content - 1) ^ "\n");
      close_out channel;
      Review.refresh review;
      await review;
      let rendered review width height =
        let view = Review_view.render review ~width ~height in
        let buffer = Buffer.create 8192 in
        Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (width, height) view.image;
        Buffer.contents buffer
      in
      let document = Option.get (Review.document review) in
      check "loaded patch indexes both real files" (Diff_document.file_count document = 2);
      Review.poll review;
      check "idle polling retains parsed document"
        (Option.get (Review.document review) == document);
      let text = rendered review 80 24 in
      check "review displays current file position"
        (Controller.contains text "file 1/2: changed.txt");
      Review.set_horizontal review 40;
      Review.key review (`ASCII ']', []);
      let target =
        Option.get (Diff_document.file_at document ~line:(Review.scroll review))
      in
      check "next file jumps to its header and resets horizontal position"
        (target.name = "long.txt"
        && target.line = Review.scroll review
        && Review.horizontal review = 0);
      let text = rendered review 80 24 in
      check "short final file stays aligned at the top"
        (Review.scroll review = target.line
        && Controller.contains text "file 2/2: long.txt");
      let rows = String.split_on_char '\n' text in
      check "file header is the first patch row"
        (Controller.contains (List.nth rows 3) "diff --git a/long.txt b/long.txt");
      Review.key review (`ASCII ']', []);
      check "next file at the last boundary stays put" (Review.scroll review = target.line);
      Review.key review (`ASCII '[', []);
      check "previous file returns to the first header" (Review.scroll review = 0);
      Review.key review (`ASCII '[', []);
      check "previous file at the first boundary stays put" (Review.scroll review = 0);
      ignore (rendered review 60 8);
      Review.key review (`Page `Down, []);
      check "page scroll uses rendered patch height" (Review.scroll review = 2);
      Review.key review (`Page `Up, []);
      check "page up returns by rendered patch height" (Review.scroll review = 0);
      Review.key review (`ASCII 'G', []);
      check "bottom uses last full viewport"
        (Review.scroll review = max 0 (Diff_document.line_count document - 2));
      Review.key review (`ASCII 'g', []);
      let text = rendered review 80 24 in
      check "long diff suffix initially clipped"
        (not (Controller.contains text "LONG_LINE_END"));
      Review.key review (`ASCII 'l', []);
      check "l moves horizontal viewport" (Review.horizontal review = 4);
      Review.key review (`Arrow `Left, []);
      check "left arrow returns horizontal viewport" (Review.horizontal review = 0);
      Review.set_horizontal review 1000000;
      let text = rendered review 80 24 in
      check "scroll reveals Unicode long-line suffix"
        (Controller.contains text "界éLONG_LINE_END");
      check "horizontal scroll clamps by terminal cells" (Review.horizontal review = 87);
      check "horizontal viewport indicator visible"
        (Controller.contains text "column +87");
      Review.key review (`ASCII '0', []);
      check "zero returns to beginning of diff" (Review.horizontal review = 0);
      Review.key review (`ASCII 'h', []);
      check "horizontal scroll cannot become negative" (Review.horizontal review = 0);
      Review.set_horizontal review 100;
      ignore (rendered review 180 24);
      check "wide resize restores unneeded horizontal offset"
        (Review.horizontal review = 0);
      Review.set_horizontal review 50;
      Review.refresh review;
      check "refresh resets horizontal viewport" (Review.horizontal review = 0);
      check "refresh clears previous file index" (Review.document review = None);
      Review.key review (`ASCII ']', []);
      check "file navigation while loading does not move viewport"
        (Review.scroll review = 0);
      await review;
      Review.edit_executable review;
      Review.key review (`ASCII 'l', []);
      check "path editing keeps navigation literal"
        (String.ends_with ~suffix:"l" (Review.executable review)
        && Review.horizontal review = 0);
      Review.key review (`Backspace, []);
      Review.key review (`ASCII ']', []);
      check "file key remains literal in path editing"
        (String.ends_with ~suffix:"]" (Review.executable review)
        && Review.scroll review = 0);
      Review.key review (`Backspace, []);
      Review.key review (`Enter, []);
      await review;
      controller.tasks <- [ task ];
      controller.selected <- task.id;
      controller.jj_executable <- jj;
      Controller.act controller Controller.Open_review;
      let review = Option.get controller.review in
      Controller.key controller (`ASCII 'r', []);
      await review;
      let frame = Ui.render controller ~width:120 ~height:36 in
      let buffer = Buffer.create 8192 in
      Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
      List.iter
        (fun (width, height) ->
          let frame = Ui.render controller ~width ~height in
          check "review overlay bounds"
            (Notty.I.width frame.image = width && Notty.I.height frame.image = height);
          List.iter
            (fun (hit : Ui.hit) ->
              let r = hit.rect in
              check "review overlay click bounds"
                (r.x >= 0 && r.y >= 0 && r.x + r.w <= width && r.y + r.h <= height))
            frame.hits)
        [ (1, 1); (20, 8); (60, 20); (120, 36); (180, 50) ];
      let before_file_navigation = Controller.snapshot controller in
      let next_file_hit =
        List.find
          (fun (hit : Ui.hit) -> hit.action = Controller.Next_review_file)
          frame.hits
      in
      Ui.mouse controller frame ~now:3.
        (`Press `Left, (next_file_hit.rect.x, next_file_hit.rect.y), []);
      check "next file button selects the second file"
        ((Option.get
            (Diff_document.file_at
               (Option.get (Review.document review))
               ~line:(Review.scroll review)))
           .index = 1);
      let previous_file_hit =
        List.find
          (fun (hit : Ui.hit) -> hit.action = Controller.Previous_review_file)
          frame.hits
      in
      Ui.mouse controller frame ~now:3.1
        (`Press `Left, (previous_file_hit.rect.x, previous_file_hit.rect.y), []);
      check "previous file button returns to first file" (Review.scroll review = 0);
      check "file navigation changes no task or saved draft"
        (Controller.snapshot controller = before_file_navigation);
      let view = Review_view.render review ~width:120 ~height:35 in
      let buffer_buttons = Buffer.create 8192 in
      Notty.Render.to_buffer buffer_buttons Notty.Cap.dumb (0, 0) (120, 35) view.image;
      let button_row =
        List.nth (String.split_on_char '\n' (Buffer.contents buffer_buttons)) 33
      in
      check "file buttons align with their visible labels"
        (String.sub button_row next_file_hit.rect.x 11 = "[Next file]"
        && String.sub button_row previous_file_hit.rect.x 11 = "[Prev file]");
      let parser = Notty.Unescape.create () in
      let bytes = Bytes.of_string "\027[<81;10;10M" in
      Notty.Unescape.input parser bytes 0 (Bytes.length bytes);
      (match Notty.Unescape.next parser with
      | `Mouse mouse ->
          Ui.mouse controller frame ~now:4. mouse;
          check "terminal Ctrl-wheel moves horizontally" (Review.horizontal review = 4)
      | _ -> failwith "Mouse scroll not decoded");
      Review.set_horizontal review 0;
      Ui.mouse controller frame ~now:5. (`Press (`Scroll `Down), (10, 10), [ `Ctrl ]);
      check "Ctrl-wheel scrolls horizontally" (Review.horizontal review = 4);
      Ui.mouse controller frame ~now:6. (`Press (`Scroll `Up), (10, 10), [ `Ctrl ]);
      check "Ctrl-wheel returns left" (Review.horizontal review = 0);
      Review.edit_executable review;
      Ui.mouse controller frame ~now:7. (`Press (`Scroll `Down), (10, 10), [ `Ctrl ]);
      check "wheel does not move diff while editing path" (Review.horizontal review = 0);
      Review.key review (`Enter, []);
      await review;
      check "real patch rendered"
        (Controller.contains (Buffer.contents buffer) "+a real addition");
      Review.refresh review;
      Controller.act controller Controller.Close_review;
      check "loading review cannot abandon owned worker" (controller.review <> None);
      await review;
      check "review blocks background buttons"
        (List.for_all
           (fun (hit : Ui.hit) ->
             match hit.action with
             | Controller.Refresh_review | Controller.Edit_review_executable
             | Controller.Close_review | Controller.Next_review_file
             | Controller.Previous_review_file ->
                 true
             | _ -> false)
           frame.hits);
      Controller.key controller (`ASCII 's', []);
      check "review cannot start agent"
        ((Option.get (Controller.selected controller)).active = None);
      Controller.key controller (`ASCII 'a', []);
      check "review cannot accept task"
        ((Option.get (Controller.selected controller)).state = Model.Queued);
      Controller.key controller (`Escape, []);
      check "escape returns to same chat"
        (controller.review = None && controller.selected = task.id);
      let board_frame = Ui.render controller ~width:120 ~height:36 in
      controller.focus <- Controller.Board;
      Ui.mouse controller board_frame ~now:8. (`Press (`Scroll `Down), (10, 10), []);
      check "plain wheel still scrolls board" (controller.board_scroll = 1);
      controller.live_confirmation <- Some task.id;
      Ui.mouse controller board_frame ~now:9. (`Press (`Scroll `Down), (10, 10), []);
      check "confirmation blocks wheel behind modal" (controller.board_scroll = 1);
      controller.live_confirmation <- None;
      let review = ok (Review.create task ~jj:"/absent/jj") in
      Review.refresh review;
      await review;
      check "missing executable returns visible error"
        (match Review.state review with Changes.Error _ -> true | _ -> false);
      Review.close review);
  Printf.printf "Passed %d changes review checks. Temporary repositories only.\n" !checks
