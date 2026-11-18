open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let () =
  let paths =
    [
      "/Users/developer/dev/factory";
      "/work/alpha/service";
      "/work/beta/service";
      "/work/beta/other";
      "plain-repo";
      "/foo";
      "foo";
    ]
  in
  let labels = Repository_labels.create paths in
  let label = Repository_labels.label labels in
  check "unique repository uses basename" (label (List.hd paths) = "factory");
  check "duplicate basename includes distinguishing parent"
    (label "/work/alpha/service" = "alpha/service"
    && label "/work/beta/service" = "beta/service");
  check "plain name is unchanged" (label "plain-repo" = "plain-repo");
  check "normalized collisions keep exact identity"
    (label "/foo" = "/foo" && label "foo" = "foo");
  check "unknown repository falls back to full name"
    (label "/unknown/repository" = "/unknown/repository");
  check "input duplicates do not lengthen labels"
    (Repository_labels.label (Repository_labels.create [ "/a/repo"; "/a/repo" ]) "/a/repo"
    = "repo");
  let nested = Repository_labels.create [ "foo"; "/a/foo"; "/x/a/foo" ] in
  check "short repository does not hide longer distinguishing paths"
    (Repository_labels.label nested "foo" = "foo"
    && Repository_labels.label nested "/a/foo" = "/a/foo"
    && Repository_labels.label nested "/x/a/foo" = "x/a/foo");
  let weird = Repository_labels.create [ "/"; ""; "/a//repo"; "/a/repo"; "界/project" ] in
  check "empty/root metadata does not raise"
    (Repository_labels.label weird "/" = "/" && Repository_labels.label weird "" = "");
  check "repeated separators remain distinguishable"
    (Repository_labels.label weird "/a//repo" = "/a//repo"
    && Repository_labels.label weird "/a/repo" = "/a/repo");
  let many =
    List.init 1000 (fun index ->
        Printf.sprintf "/same/long/prefix/team-%04d/service" index)
  in
  let many_labels = Repository_labels.create many in
  let displayed = List.map (Repository_labels.label many_labels) many in
  check "large shared-prefix inventory keeps distinct repository labels"
    (List.length (List.sort_uniq String.compare displayed) = List.length many);
  check "shared prefix is omitted without losing distinguishing parents"
    (List.hd displayed = "team-0000/service");
  let repeated = Repository_labels.create (List.rev paths @ paths) in
  check "label choice is independent of inventory order and duplicate tasks"
    (List.for_all (fun path -> Repository_labels.label repeated path = label path) paths);
  let controller = Controller.create ~external_events:true () in
  let first =
    Model.make ~id:"alpha-task" ~title:"Alpha task" ~repository:"/work/alpha/service"
  in
  let second =
    Model.make ~id:"beta-task" ~title:"Beta task" ~repository:"/work/beta/service"
  in
  controller.tasks <- [ first; second ];
  controller.selected <- first.id;
  let saved = Controller.snapshot controller in
  let render () =
    let frame = Ui.render controller ~width:180 ~height:50 in
    let buffer = Buffer.create 8192 in
    Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (180, 50) frame.image;
    (frame, Buffer.contents buffer)
  in
  let frame, text = render () in
  check "cards and sidebar show distinguishing suffixes"
    (Controller.contains text "alpha/service" && Controller.contains text "beta/service");
  check "Activity still exposes full repository identity"
    (Controller.contains text "repo: /work/alpha/service");
  let target =
    List.find
      (fun (hit : Ui.hit) -> hit.action = Controller.Repository (Some second.repository))
      frame.hits
  in
  Ui.mouse controller frame ~now:1. (`Press `Left, (target.rect.x, target.rect.y), []);
  check "short display label filters by exact original path"
    (controller.repository = Some second.repository
    && List.map (fun (task : Model.task) -> task.id) (Controller.visible controller)
       = [ second.id ]);
  let _, text = render () in
  check "filtered board keeps stable label computed across all tasks"
    (Controller.contains text "beta/service");
  check "label calculation and filtering change no saved task content"
    (Controller.snapshot controller = saved);
  Printf.printf
    "Passed %d repository display-label checks. No path or workspace operations.\n"
    !checks
