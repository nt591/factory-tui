open Factory_tui
open Model

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  let root = Filename.temp_file "factory-root" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let root = Unix.realpath root in
  Fun.protect
    ~finally:(fun () -> Unix.rmdir root)
    (fun () ->
      let original =
        Model.make ~id:"root-task" ~title:"Work across services" ~repository:""
      in
      let task = ok (Model.attach_root original root) in
      check "root attaches without a repository"
        (task.session_root = Some root && task.workspace = None && task.repository = root);
      check "root identity cannot change on existing task"
        (Result.is_error (Model.attach_root task root));
      let saved : Snapshot.t =
        { tasks = [ task ]; drafts = []; selected = task.id; serial = 300 }
      in
      check "root survives snapshot roundtrip"
        (ok (Snapshot.decode (Snapshot.encode saved)) = saved);
      let cfg = ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None) in
      let invocation, prompt = ok (Live_runner.prepare cfg task) in
      check "live root uses exact cwd and queued instruction"
        (invocation.directory = root && prompt = task.title
        && List.mem "--skip-git-repo-check" invocation.arguments);
      let write =
        ok (Model.start ~simulated:false ~policy:Workspace_write task "write-run")
      in
      check "write run on explicit root stays durable"
        (Result.is_ok
           (Snapshot.decode (Snapshot.encode { saved with tasks = [ write ] })));
      check "simulated root cannot request writes"
        (Result.is_error (Model.start ~policy:Workspace_write task "fake-write"));
      let ambiguous =
        {
          task with
          workspace =
            Some
              {
                source = "/fixture/source";
                directory = "/fixture/checkout";
                base = String.make 40 'a';
                name = "fixture";
              };
        }
      in
      check "snapshot rejects simultaneous root and workspace"
        (Result.is_error
           (Snapshot.decode (Snapshot.encode { saved with tasks = [ ambiguous ] })));
      check "snapshot rejects mismatched root repository label"
        (Result.is_error
           (Snapshot.decode
              (Snapshot.encode
                 { saved with tasks = [ { task with repository = "/wrong" } ] })));
      let running = ok (Model.start ~simulated:false task "run") in
      check "Working root survives recovery without losing identity"
        ((List.hd (Snapshot.recover { saved with tasks = [ running ] }).tasks)
           .session_root = Some root);
      let workspace =
        {
          source = "/fixture/source";
          directory = "/fixture/isolated";
          base = String.make 40 'a';
          name = "fixture";
        }
      in
      check "root cannot attach repository identity accidentally"
        (Result.is_error (Model.attach_workspace task workspace));
      List.iter
        (fun path ->
          check "invalid root refused" (Result.is_error (Model.attach_root original path)))
        [ "relative"; "/tmp/../root"; "/tmp/root\n" ];
      let request : Task_creation.request =
        {
          id = "folder";
          greenfield = false;
          folder_root = true;
          jj = "";
          source = root;
          parent = "";
          revision = "";
          model = "fixture";
          instruction = String.make 119 'x' ^ "界";
        }
      in
      let job = Task_creation.start request in
      Task_creation.close job;
      let created =
        match Task_creation.result job with
        | Some result -> ok result
        | None -> failwith "missing result"
      in
      check "root creation requires no jj parent revision or files"
        (created.session_root = Some root
        && Sys.readdir root = [||]
        && String.ends_with ~suffix:"界" created.title);
      let controller = Controller.create () in
      controller.database_path <- Some "/fixture/not-opened.sqlite";
      Controller.act controller Begin_workspace;
      let form = Option.get controller.workspace_form in
      let fill field value =
        Workspace_form.focus form field;
        String.iter (fun c -> Workspace_form.key form (`ASCII c, [])) value
      in
      fill Workspace_form.Source root;
      fill Workspace_form.Task "Root work";
      Controller.act controller Toggle_folder_root;
      check "folder form validates without jj parent or revision"
        (Result.is_ok (Workspace_form.validate form));
      Controller.act controller Submit_workspace;
      check "creation request captures folder mode"
        (Option.get controller.creation_request).folder_root;
      let frame = Ui.render controller ~width:120 ~height:36 in
      let buffer = Buffer.create 2000 in
      Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (120, 36) frame.image;
      check "form discloses no checkout creation"
        (Controller.contains (Buffer.contents buffer) "FOLDER ROOT");
      let view = Live_confirmation.render (Some task) ~width:100 ~height:50 in
      Buffer.clear buffer;
      Notty.Render.to_buffer buffer Notty.Cap.dumb (0, 0) (100, 50) view.image;
      check "confirmation distinguishes root from sandbox"
        (Controller.contains (Buffer.contents buffer) "Session root:"
        && Controller.contains (Buffer.contents buffer) "no isolated checkout"));
  Printf.printf
    "Passed %d session-root checks. Temporary empty folder; no network/agent/repository.\n"
    !checks
