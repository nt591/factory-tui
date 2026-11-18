open Factory_tui
open Controller

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let wait picker =
  let rec loop n =
    Model_picker.poll picker;
    match Model_picker.state picker with
    | Loading when n > 0 ->
        Thread.delay 0.001;
        loop (n - 1)
    | Loading -> failwith "fixture worker did not finish"
    | _ -> ()
  in
  loop 2000

let () =
  let picker = Model_picker.create () in
  check "opening picker does not fetch" (Model_picker.state picker = Idle);
  let release = ref false and calls = ref 0 in
  Model_picker.refresh picker (fun () ->
      incr calls;
      while not !release do
        Thread.delay 0.001
      done;
      Ok [ "alpha"; "beta"; "provider/model" ]);
  Model_picker.refresh picker (fun () -> failwith "duplicate request");
  check "worker runs asynchronously" (Model_picker.state picker = Loading);
  release := true;
  wait picker;
  check "single request result appears"
    (!calls = 1 && Model_picker.selected picker = Some "alpha");
  Model_picker.move picker 1;
  check "arrow motion follows catalogue" (Model_picker.selected picker = Some "beta");
  Model_picker.insert picker "PROVIDER";
  check "literal filter is ASCII case insensitive"
    (Model_picker.visible picker = [ "provider/model" ]);
  Model_picker.reset picker;
  Model_picker.insert picker (String.make 257 'a');
  check "oversized filter is not applied" (Model_picker.query picker = "");
  Model_picker.refresh picker (fun () -> Error "Fixture error");
  wait picker;
  check "error remains inspectable" (Model_picker.state picker = Error "Fixture error");
  Model_picker.refresh picker (fun () -> failwith "hidden exception");
  wait picker;
  check "worker exceptions do not expose details"
    (Model_picker.state picker = Error "Model discovery failed. Diagnostics withheld.");
  let controller = Controller.create ~external_events:true () in
  Controller.act controller Open_models;
  let selected = controller.selected in
  let saved = Controller.snapshot controller in
  check "opening modal changes no persisted data" (Controller.snapshot controller = saved);
  Model_picker.refresh controller.model_picker (fun () ->
      Ok [ "fixture-model"; "other-model" ]);
  wait controller.model_picker;
  let render w h = Ui.render controller ~width:w ~height:h in
  List.iter
    (fun (w, h) ->
      let frame = render w h in
      check "picker frame and targets fit terminal"
        (Notty.I.width frame.image = w
        && Notty.I.height frame.image = h
        && List.for_all
             (fun (hit : Ui.hit) ->
               let r = hit.rect in
               r.x >= 0 && r.y >= 0 && r.x + r.w <= w && r.y + r.h <= h)
             frame.hits);
      check "picker hides underlying process/editor controls"
        (List.for_all
           (fun (hit : Ui.hit) ->
             match hit.action with
             | Refresh_models | Close_models | Choose_model _ -> true
             | _ -> false)
           frame.hits
        && frame.input_controls = []))
    [ (1, 1); (20, 8); (60, 20); (120, 36); (180, 50) ];
  Controller.key controller (`ASCII 's', []);
  check "typing s filters rather than starts"
    (Model_picker.query controller.model_picker = "s"
    && Controller.snapshot controller = saved);
  Model_picker.reset controller.model_picker;
  Controller.paste_key controller (`Enter, []);
  check "pasted Enter cannot choose model" (controller.model_target = Some selected);
  Controller.key controller (`Enter, []);
  check "Enter applies chosen next-run model only"
    (controller.model_target = None
    && (Option.get (Controller.selected controller)).model = "fixture-model"
    && (Option.get (Controller.selected controller)).runs
       = (List.find (fun (task : Model.task) -> task.id = selected) saved.tasks).runs);
  Controller.act controller Open_models;
  let frame = render 120 36 in
  let hit = List.find (fun (hit : Ui.hit) -> hit.action = Close_models) frame.hits in
  Ui.mouse controller frame ~now:0. (`Press `Left, (hit.rect.x, hit.rect.y), []);
  check "mouse close retains current model" (controller.model_target = None);
  Controller.act controller Open_models;
  controller.selected <- "T-101";
  Controller.act controller (Choose_model "other-model");
  check "different selected task rejects stale catalogue choice"
    ((Option.get (Controller.selected controller)).model <> "other-model");
  Controller.act controller Close_models;
  Controller.act controller (Select selected);
  controller.tasks <-
    List.map
      (fun (task : Model.task) ->
        if task.id = selected then { task with state = Done } else task)
      controller.tasks;
  Controller.act controller Open_models;
  check "accepted task cannot open editor catalogue" (controller.model_target = None);
  Model_picker.close controller.model_picker;
  Model_picker.close picker;
  Printf.printf
    "Passed %d model-picker checks. Fixture workers only; no network/key/agent.\n" !checks
