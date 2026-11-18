open Factory_tui
open Controller

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let settings =
    ok
      (Config.parse ~base:"/fixture" ~home:"/home/fixture"
         "[projects.api]\n\
          source='api'\n\
          description='API service'\n\
          revision='main'\n\
          [projects.worker]\n\
          source='~/worker'\n\
          description='Job processing'")
  in
  check "registered projects sorted with resolved paths"
    (List.map (fun (p : Project.t) -> (p.name, p.source, p.revision)) settings.projects
    = [ ("api", "/fixture/api", "main"); ("worker", "/home/fixture/worker", "@") ]);
  List.iter
    (fun text ->
      check "invalid catalogue refused"
        (Result.is_error (Config.parse ~base:"/fixture" ~home:"/home" text)))
    [
      "[projects.api]\nsource=''";
      "[projects.api]\nsource='api'\nsecret='forbidden'";
      "projects=3";
      "[projects.api]\nsource='api'\nrevision='-option'";
      "[projects.'bad name']\nsource='api'";
    ];
  let controller = Controller.create () in
  controller.database_path <- Some "/fixture/unused.sqlite";
  controller.projects <- settings.projects;
  Controller.act controller Begin_workspace;
  let form = Option.get controller.workspace_form in
  Workspace_form.focus form Task;
  Workspace_form.key form (`ASCII 'x', []);
  let model = Workspace_form.value form Model
  and parent = Workspace_form.value form Parent in
  let saved = Controller.snapshot controller in
  Controller.key controller (`ASCII 'p', [ `Ctrl ]);
  let picker = Option.get controller.project_picker in
  Project_picker.insert picker "processing";
  check "filter finds project by description"
    ((Option.get (Project_picker.selected picker)).name = "worker");
  Controller.paste_key controller (`Enter, []);
  check "pasted Enter cannot choose project" (controller.project_picker <> None);
  Controller.key controller (`Enter, []);
  check "project selection fills form without task creation"
    (controller.project_picker = None
    && Workspace_form.value form Source = "/home/fixture/worker"
    && Workspace_form.value form Revision = "@"
    && Workspace_form.value form Task = "x"
    && Workspace_form.value form Model = model
    && Workspace_form.value form Parent = parent
    && Controller.snapshot controller = saved
    && controller.creation_request = None);
  Controller.act controller Open_projects;
  let render w h = Ui.render controller ~width:w ~height:h in
  List.iter
    (fun (w, h) ->
      let frame = render w h in
      check "project overlay targets fit terminal and isolate input"
        (List.for_all
           (fun (hit : Ui.hit) ->
             let r = hit.rect in
             r.x >= 0 && r.y >= 0
             && r.x + r.w <= w
             && r.y + r.h <= h
             &&
             match hit.action with
             | Choose_project _ | Close_projects -> true
             | _ -> false)
           frame.hits
        && frame.input_controls = []))
    [ (1, 1); (20, 8); (60, 20); (120, 36); (180, 50) ];
  let frame = render 120 36 in
  let hit =
    List.find (fun (hit : Ui.hit) -> hit.action = Choose_project "api") frame.hits
  in
  Ui.mouse controller frame ~now:1. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  check "mouse selects exact project revision"
    (Workspace_form.value form Source = "/fixture/api"
    && Workspace_form.value form Revision = "main");
  Controller.act controller Open_projects;
  Controller.key controller (`ASCII 's', [ `Ctrl ]);
  check "picker blocks creation shortcut" (controller.creation_request = None);
  Controller.act controller Cancel_workspace;
  Controller.act controller Begin_workspace;
  let replacement = Option.get controller.workspace_form in
  Controller.act controller (Choose_project "worker");
  check "replaced form cannot receive stale project"
    (Workspace_form.value replacement Source <> "/home/fixture/worker");
  Controller.act controller Close_projects;
  Workspace_form.focus replacement Parent;
  Workspace_form.key replacement (`ASCII '/', []);
  Workspace_form.focus replacement Task;
  Workspace_form.key replacement (`ASCII 'x', []);
  Controller.act controller Toggle_greenfield;
  check "greenfield does not require project selection"
    (Workspace_form.greenfield replacement);
  Controller.act controller Open_projects;
  Controller.act controller (Choose_project "api");
  check "selecting project explicitly restores existing-project mode"
    (not (Workspace_form.greenfield replacement));
  Printf.printf
    "Passed %d project catalogue checks. Pure config/form/renderer; no repository access.\n"
    !checks
