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
        (Review.state review = Changes.Idle && Review.editing review);
      Review.key review (`Enter, []);
      check "invalid path does not spawn"
        (Review.state review = Changes.Idle && Review.status review <> None);
      String.iter (fun char -> Review.key review (`ASCII char, [])) jj;
      Review.paste_key review (`Enter, []);
      check "paste cannot start refresh" (Review.state review = Changes.Idle);
      Review.key review (`Enter, []);
      await review;
      check "empty workspace has real empty patch" (Review.state review = Changes.Patch "");
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
             | Controller.Close_review ->
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
      let review = ok (Review.create task ~jj:"/absent/jj") in
      Review.refresh review;
      await review;
      check "missing executable returns visible error"
        (match Review.state review with Changes.Error _ -> true | _ -> false);
      Review.close review);
  Printf.printf "Passed %d changes review checks. Temporary repositories only.\n" !checks
