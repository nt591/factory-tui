open Model

type focus = Board | Conversation | Activity
type input = Normal | Search | Chat_search | Compose | New_task | Edit_model
type menu_tab = Help_tab | Settings_tab
type prefix = No_prefix | Go | Window
type model_target = Task_model of string | Workspace_model of Workspace_form.t

type action =
  | Select of string
  | Zoom
  | Open_conversation
  | Back
  | Begin_delete
  | Cancel_delete
  | Confirm_delete
  | Focus of focus
  | Start
  | Stop
  | Accept
  | Restore_task
  | Repository of string option
  | Session_board
  | Archive_view
  | Reveal_selected
  | Menu_tab of menu_tab
  | Close_menu
  | Toggle_raw_tools
  | Toggle_tools
  | Next_repository
  | Next_harness
  | Begin_model
  | Toggle_folder_root
  | Toggle_greenfield
  | Open_projects
  | Close_projects
  | Choose_project of string
  | Open_models
  | Refresh_models
  | Close_models
  | Choose_model of string
  | Toggle_archive
  | Toggle_pause
  | Help
  | Quit
  | Begin_chat_search
  | Next_chat_match
  | Previous_chat_match
  | Clear_chat_search
  | Follow_chat
  | Begin_search
  | Begin_compose
  | Open_review
  | Refresh_review
  | Edit_review_executable
  | Close_review
  | Next_review_file
  | Previous_review_file
  | Begin_workspace
  | Submit_workspace
  | Send_workspace
  | Cancel_workspace
  | Workspace_field of Workspace_form.field
  | Begin_new

type t = {
  mutable projects : Project.t list;
  mutable project_picker : Project_picker.t option;
  model_picker : Model_picker.t;
  mutable model_target : model_target option;
  mutable live_config : Live_runner.config option;
  mutable live_waiting_tasks : string list;
  mutable owned_tasks : string list;
  mutable deletion : Task_deletion.t option;
  mutable deletion_request : string option;
  mutable review : Review.t option;
  mutable jj_executable : string;
  mutable workspace_defaults : Workspace_defaults.t;
  mutable workspace_form : Workspace_form.t option;
  mutable creation_job : Task_creation.job option;
  mutable creation_send : bool;
  mutable creation_request : Task_creation.request option;
  mutable tasks : task list;
  task_updates : Task_updates.t;
  mutable selected : string;
  mutable focus : focus;
  mutable zoom : bool;
  mutable activity_expanded : bool;
  mutable activity_origin_zoom : bool;
  mutable archive : bool;
  mutable paused : bool;
  mutable help : bool;
  mutable menu_tab : menu_tab;
  mutable menu_scroll : int;
  mutable menu_page_rows : int;
  mutable repository : string option;
  mutable sidebar_scroll : int option;
  mutable tools_expanded : bool;
  mutable raw_tools : bool;
  mutable database_path : string option;
  mutable input : input;
  mutable input_limit : int option;
  mutable input_error : string option;
  mutable query : string;
  chat_search : Chat_search.t;
  chat_viewport : Chat_viewport.t;
  chat_layout : Chat_layout.t;
  tool_cache : Tool_cache.t;
  mutable new_title : string;
  mutable model_text : string;
  mutable editor : Text_edit.t;
  mutable drafts : (string * string) list;
  mutable scroll : int;
  mutable board_scroll : int;
  mutable board_list : bool;
  column_scroll : Column_scroll.t;
  pane_scroll : Pane_scroll.t;
  pane_layout : Pane_layout.t;
  mutable status : string;
  mutable quit : bool;
  mutable serial : int;
  mutable schedules : (float * envelope) list;
  mutable last_click : (string * float) option;
  mutable prefix : prefix;
  mutable count : int;
  mutable page_rows : int;
  mutable storage_events : envelope list;
  mutable retain_events : bool;
  fake_harness : bool;
  external_events : bool;
}

let create ?(external_events = false) ?(fake_harness = false) () =
  {
    projects = [];
    project_picker = None;
    model_picker = Model_picker.create ();
    model_target = None;
    live_config = None;
    live_waiting_tasks = [];
    owned_tasks = [];
    deletion = None;
    deletion_request = None;
    review = None;
    jj_executable = "";
    workspace_defaults = Workspace_defaults.empty;
    workspace_form = None;
    creation_job = None;
    creation_request = None;
    creation_send = false;
    task_updates = Task_updates.create ();
    tasks =
      (if fake_harness then
         (Snapshot.recover
            { tasks = Demo.Seed.seed (); drafts = []; selected = "T-102"; serial = 200 })
           .tasks
       else Demo.Seed.seed ());
    selected = "T-102";
    focus = Board;
    zoom = false;
    activity_expanded = false;
    activity_origin_zoom = false;
    archive = false;
    paused = false;
    help = false;
    menu_tab = Help_tab;
    menu_scroll = 0;
    menu_page_rows = 8;
    repository = None;
    sidebar_scroll = None;
    tools_expanded = false;
    raw_tools = false;
    database_path = None;
    input = Normal;
    input_limit = None;
    input_error = None;
    query = "";
    chat_search = Chat_search.create ();
    chat_viewport = Chat_viewport.create ();
    chat_layout = Chat_layout.create ();
    tool_cache = Tool_cache.create ();
    new_title = "";
    model_text = "";
    editor = Text_edit.create "";
    drafts = [];
    scroll = 0;
    board_scroll = 0;
    board_list = false;
    column_scroll = Column_scroll.create ();
    pane_scroll = Pane_scroll.create ();
    pane_layout = Pane_layout.create ();
    status = "Simulation only. No agent, credentials, or workspace access.";
    quit = false;
    serial = 200;
    schedules =
      (if external_events || fake_harness then []
       else
         List.map
           (fun (delay, e) -> (Unix.gettimeofday () +. delay, e))
           (Demo.Seed.schedule "T-102" "demo-102"));
    last_click = None;
    prefix = No_prefix;
    count = 0;
    page_rows = 12;
    storage_events = [];
    retain_events = false;
    fake_harness;
    external_events;
  }

let contains text query = Literal_search.contains (Literal_search.prepare query) text

let visible t =
  let search = Literal_search.prepare t.query in
  List.filter
    (fun (task : task) ->
      (if t.archive then task.state = Done else task.state <> Done)
      && (match t.repository with
        | None -> true
        | Some repository -> task.repository = repository)
      && Literal_search.contains search
           (task.id ^ " " ^ task.title ^ " " ^ task.repository))
    t.tasks

let repositories t =
  List.map (fun (task : task) -> task.repository) t.tasks |> List.sort_uniq String.compare

let selected t = List.find_opt (fun (task : task) -> task.id = t.selected) t.tasks
let draft t = Option.value ~default:"" (List.assoc_opt t.selected t.drafts)

let set_draft t text =
  t.drafts <- (t.selected, text) :: List.remove_assoc t.selected t.drafts

let next_id t prefix =
  let id, serial = Id_allocation.next ~prefix ~serial:t.serial t.tasks in
  t.serial <- serial;
  id

let replace t (task : task) =
  (if task.id = t.selected then
     match List.find_opt (fun (old : task) -> old.id = task.id) t.tasks with
     | Some old when old.state <> task.state ->
         Column_scroll.follow t.column_scroll task.state
     | _ -> ());
  t.tasks <- List.map (fun (old : task) -> if old.id = task.id then task else old) t.tasks

let reset_keys t =
  t.prefix <- No_prefix;
  t.count <- 0

let reset_chat_view t =
  Chat_viewport.reset t.chat_viewport;
  Pane_scroll.remember t.pane_scroll Chat 0

let select t id =
  if t.selected <> id then Chat_search.clear t.chat_search;
  t.selected <- id;
  Option.iter
    (fun (task : task) -> Column_scroll.follow t.column_scroll task.state)
    (selected t);
  reset_chat_view t;
  Pane_scroll.clear t.pane_scroll;
  t.scroll <- 0;
  t.board_scroll <- 0;
  Option.iter
    (fun task ->
      if not (String.starts_with ~prefix:"Storage error:" t.status) then
        t.status <-
          Task_guidance.selection ~live:(t.live_config <> None) ~replay:t.external_events
            task)
    (selected t)

let repair_selection t =
  if not (List.exists (fun (task : task) -> task.id = t.selected) (visible t)) then
    match visible t with task :: _ -> select t task.id | [] -> t.selected <- ""

let ensure_selection t = if selected t = None then repair_selection t

let receive t event =
  let previous_state = Option.map (fun (task : task) -> task.state) (selected t) in
  let tasks = reduce t.tasks event in
  let changed = tasks <> t.tasks in
  if changed then Task_updates.record t.task_updates event;
  if changed && t.retain_events then t.storage_events <- t.storage_events @ [ event ];
  t.tasks <- tasks;
  Option.iter
    (fun (task : task) ->
      if changed && previous_state <> Some task.state then
        Column_scroll.follow t.column_scroll task.state)
    (selected t);
  (* Persistence failures take priority over run guidance because updates can be unsaved. *)
  if
    changed && event.task_id = t.selected
    && not (String.starts_with ~prefix:"Storage error:" t.status)
  then
    match (event.event, selected t) with
    | Turn_started, Some _ ->
        t.status <- "Run started. x stops; replies queue for the next turn."
    | Exited _, Some task when task.state = Ready ->
        t.status <-
          (if task.session_root <> None then
             "Run complete. Review files in the session root; Ctrl-A archives without \
              merging."
           else "Run complete. v reviews changes; Ctrl-A archives without merging.")
    | Exited _, Some task when task.state = Needs_you ->
        t.status <- "Run needs attention. Inspect the chat; i queues a reply."
    | Interrupted, Some _ -> t.status <- "Run stopped. i queues a reply; s retries."
    | _ -> ()

let snapshot t : Snapshot.t =
  { tasks = t.tasks; drafts = t.drafts; selected = t.selected; serial = t.serial }

let restore t saved =
  Task_updates.reset t.task_updates;
  let guidance = Restart_guidance.describe saved in
  let saved = Snapshot.recover saved in
  t.tasks <- saved.tasks;
  t.drafts <- saved.drafts;
  t.selected <- saved.selected;
  t.serial <- saved.serial;
  t.schedules <- [];
  (* Board filters must not replace a retained conversation during restart. *)
  let selection =
    match selected t with
    | Some task -> Some task
    | None -> (
        match visible t with task :: _ -> Some task | [] -> List.nth_opt t.tasks 0)
  in
  (match selection with Some task -> select t task.id | None -> t.selected <- "");
  t.status <- guidance

let tick t now =
  if not t.paused then (
    let due, later = List.partition (fun (time, _) -> time <= now) t.schedules in
    t.schedules <- later;
    List.iter (fun (_, event) -> receive t event) due)

let focus_pane t focus =
  if t.focus <> focus then (
    (match t.focus with
    | Conversation -> Pane_scroll.remember t.pane_scroll Chat t.scroll
    | Activity -> Pane_scroll.remember t.pane_scroll Activity t.scroll
    | Board -> ());
    t.scroll <-
      (match focus with
      | Conversation -> Pane_scroll.position t.pane_scroll Chat
      | Activity -> Pane_scroll.position t.pane_scroll Activity
      | Board -> 0));
  if focus <> Activity then (
    if focus = Board && t.activity_expanded then t.zoom <- false;
    t.activity_expanded <- false);
  t.focus <- focus

let close_expansion t =
  let focus = if t.activity_expanded then Activity else Board in
  t.zoom <- (if t.activity_expanded then t.activity_origin_zoom else false);
  t.activity_expanded <- false;
  focus_pane t focus

let deletion_busy t id =
  List.mem id t.owned_tasks
  || List.mem id t.live_waiting_tasks
  || List.exists
       (fun (task : task) ->
         task.id = id && (task.active <> None || task.state = Working))
       t.tasks

let deleted_snapshot t id =
  let saved = snapshot t in
  let tasks = List.filter (fun (task : task) -> task.id <> id) saved.tasks in
  let selected =
    if saved.selected <> id then saved.selected
    else
      match List.filter (fun (task : task) -> task.id <> id) (visible t) with
      | task :: _ -> task.id
      | [] -> ""
  in
  { saved with tasks; drafts = List.remove_assoc id saved.drafts; selected }

let remove_task t id =
  let saved = deleted_snapshot t id in
  t.tasks <- saved.tasks;
  t.drafts <- saved.drafts;
  t.storage_events <- List.filter (fun event -> event.task_id <> id) t.storage_events;
  t.schedules <- List.filter (fun (_, event) -> event.task_id <> id) t.schedules;
  Task_updates.clear t.task_updates id;
  t.deletion <- None;
  t.deletion_request <- None;
  t.input <- Normal;
  t.editor <- Text_edit.create "";
  t.last_click <- None;
  if t.selected = id then (
    t.selected <- saved.selected;
    Chat_search.clear t.chat_search;
    Chat_layout.clear t.chat_layout;
    Tool_cache.clear t.tool_cache;
    reset_chat_view t;
    Pane_scroll.clear t.pane_scroll;
    t.scroll <- 0);
  t.zoom <- false;
  focus_pane t Board;
  t.status <- "Task deleted. Workspace files and agent-owned history are unchanged."

let poll_deletion t ~storage =
  match t.deletion_request with
  | None -> ()
  | Some id -> (
      t.deletion_request <- None;
      if deletion_busy t id then (
        t.deletion <- None;
        t.status <- "Task is still running. Stop it and wait for process cleanup.")
      else
        let result =
          match storage with
          | None -> Error "Persistent storage is required to delete this task."
          | Some worker -> (
              match Persistence.flush worker with
              | Error error -> Error error
              | Ok () -> (
                  let events =
                    List.filter (fun event -> event.task_id <> id) t.storage_events
                  in
                  match Persistence.submit worker (deleted_snapshot t id) ~events with
                  | Error error -> Error error
                  | Ok () -> Persistence.flush worker))
        in
        (* Keep the task visible until its deletion has a durable checkpoint. *)
        match result with
        | Error error -> t.status <- "Storage error: " ^ error
        | Ok () ->
            remove_task t id;
            t.storage_events <- [])

let report_creation t text =
  t.status <- text;
  Option.iter (fun form -> Workspace_form.report form text) t.workspace_form

let rec act t action =
  reset_keys t;
  t.input_limit <- None;
  t.input_error <- None;
  match action with
  | Select id ->
      select t id;
      focus_pane t Board
  | Focus focus -> focus_pane t focus
  | Open_conversation ->
      t.zoom <- true;
      focus_pane t Conversation;
      act t Begin_compose
  | Back ->
      if t.input <> Normal then t.input <- Normal
      else if Chat_search.query t.chat_search <> "" && t.focus = Conversation then
        Chat_search.clear t.chat_search
      else if t.zoom then close_expansion t
      else if t.focus <> Board then focus_pane t Board
      else (
        t.query <- "";
        if t.archive then act t Session_board else ensure_selection t)
  | Begin_delete -> (
      match selected t with
      | None -> ()
      | Some task ->
          if String.starts_with ~prefix:"Storage error:" t.status then ()
          else if deletion_busy t task.id then
            t.status <-
              "Stop the task with x and wait for process cleanup before deleting it."
          else t.deletion <- Some (Task_deletion.create task))
  | Cancel_delete ->
      t.deletion <- None;
      t.deletion_request <- None
  | Confirm_delete -> (
      match t.deletion with
      | None -> ()
      | Some dialog when not (Task_deletion.ready dialog) -> ()
      | Some dialog ->
          let id = Task_deletion.id dialog in
          if String.starts_with ~prefix:"Storage error:" t.status then ()
          else if deletion_busy t id then (
            t.deletion <- None;
            t.status <- "Task is still running. Stop it and wait for process cleanup.")
          else if t.database_path = None then remove_task t id
          else t.deletion_request <- Some id)
  | Zoom ->
      if t.activity_expanded || (t.zoom && t.focus = Conversation) then ()
      else if t.focus = Activity then (
        t.activity_origin_zoom <- t.zoom;
        t.zoom <- true;
        t.activity_expanded <- true)
      else (
        t.zoom <- true;
        focus_pane t Conversation;
        reset_chat_view t;
        t.scroll <- 0)
  | Quit -> t.quit <- true
  | Help ->
      t.help <- not t.help;
      t.menu_tab <- Help_tab;
      t.menu_scroll <- 0
  | Close_menu ->
      t.help <- false;
      t.menu_scroll <- 0
  | Menu_tab tab ->
      t.menu_tab <- tab;
      t.menu_scroll <- 0
  | Toggle_raw_tools ->
      t.raw_tools <- not t.raw_tools;
      t.tools_expanded <- true
  | Toggle_tools -> t.tools_expanded <- not t.tools_expanded
  | Repository repository ->
      t.repository <- repository;
      t.sidebar_scroll <- None;
      t.board_scroll <- 0;
      Column_scroll.clear t.column_scroll;
      focus_pane t Board
  | Archive_view ->
      t.archive <- true;
      t.board_scroll <- 0;
      ensure_selection t;
      focus_pane t Board;
      t.zoom <- false
  | Session_board ->
      t.sidebar_scroll <- None;
      t.query <- "";
      t.archive <- false;
      t.repository <- None;
      t.board_scroll <- 0;
      Column_scroll.clear t.column_scroll;
      focus_pane t Board;
      t.zoom <- false
  | Reveal_selected -> (
      match selected t with
      | None -> ()
      | Some task ->
          t.archive <- task.state = Done;
          t.repository <- None;
          t.query <- "";
          t.sidebar_scroll <- None;
          t.board_scroll <- 0;
          Column_scroll.clear t.column_scroll;
          Column_scroll.follow t.column_scroll task.state;
          focus_pane t Board;
          t.zoom <- false)
  | Next_repository ->
      let options =
        None :: List.map (fun repository -> Some repository) (repositories t)
      in
      let rec next = function
        | current :: following :: _ when current = t.repository -> following
        | _ :: rest -> next rest
        | [] -> None
      in
      t.repository <- next options;
      t.sidebar_scroll <- None;
      t.board_scroll <- 0;
      Column_scroll.clear t.column_scroll;
      focus_pane t Board
  | Begin_chat_search -> (
      match selected t with
      | None -> ()
      | Some _ ->
          t.input <- Chat_search;
          focus_pane t Conversation;
          t.editor <- Text_edit.create (Chat_search.query t.chat_search))
  | Next_chat_match | Previous_chat_match ->
      Option.iter
        (fun (task : task) -> Chat_search.sync t.chat_search task.messages)
        (selected t);
      Chat_search.move t.chat_search ~backwards:(action = Previous_chat_match);
      focus_pane t Conversation
  | Clear_chat_search -> Chat_search.clear t.chat_search
  | Follow_chat ->
      focus_pane t Conversation;
      reset_chat_view t;
      t.scroll <- 0;
      (* A pending search seek must not replace the explicit latest position. *)
      ignore (Chat_search.seek t.chat_search)
  | Begin_search ->
      t.input <- Search;
      t.editor <- Text_edit.create t.query
  | Begin_compose -> (
      match selected t with
      | None -> ()
      | Some task when task.state = Done -> t.status <- "Accepted tasks are read-only."
      | Some _ ->
          t.input <- Compose;
          t.editor <- Text_edit.create (draft t);
          focus_pane t Conversation)
  | Next_harness -> (
      match selected t with
      | None -> ()
      | Some task when task.state = Done -> t.status <- "Accepted tasks are read-only."
      | Some task when t.live_config <> None && task.harness = Codex ->
          t.status <- "Live execution supports Codex only. No selection changed."
      | Some task -> (
          match
            set_harness task
              (if t.live_config <> None then Codex
               else match task.harness with Codex -> Claude | Claude -> Codex)
          with
          | Error error -> t.status <- error
          | Ok task ->
              replace t task;
              t.status <- "Next-run harness selection only. No agent starts."))
  | Begin_model -> (
      match selected t with
      | None -> ()
      | Some task when task.state = Done -> t.status <- "Accepted tasks are read-only."
      | Some task ->
          t.model_text <- task.model;
          t.input <- Edit_model;
          t.editor <- Text_edit.create task.model)
  | Toggle_folder_root -> (
      match t.workspace_form with
      | Some form when t.creation_request = None && t.creation_job = None ->
          Workspace_form.toggle_folder_root form
      | _ -> ())
  | Toggle_greenfield -> (
      match t.workspace_form with
      | Some form when t.creation_request = None && t.creation_job = None ->
          Workspace_form.toggle_greenfield form
      | _ -> ())
  | Open_projects -> (
      match t.workspace_form with
      | Some form
        when t.model_target = None && t.creation_job = None && t.creation_request = None
        ->
          t.project_picker <- Some (Project_picker.create ~form t.projects)
      | _ -> ())
  | Close_projects -> t.project_picker <- None
  | Choose_project name -> (
      match (t.project_picker, t.workspace_form) with
      | Some picker, Some form
        when Project_picker.form picker == form
             && t.creation_job = None && t.creation_request = None -> (
          match
            List.find_opt
              (fun (project : Project.t) -> project.name = name)
              (Project_picker.visible picker)
          with
          | Some project ->
              Workspace_form.set_project form project;
              t.project_picker <- None
          | None -> ())
      | _ -> ())
  | Open_models when t.review <> None -> ()
  | Open_models ->
      (match t.workspace_form with
      | Some form when t.creation_job = None && t.creation_request = None ->
          t.model_target <- Some (Workspace_model form);
          Model_picker.reset t.model_picker
      | Some _ -> ()
      | None -> (
          match selected t with
          | Some task when task.state <> Done ->
              t.help <- false;
              t.input <- Normal;
              t.model_target <- Some (Task_model task.id);
              Model_picker.reset t.model_picker
          | _ -> ()));
      if t.model_target <> None then (
        Model_picker.poll t.model_picker;
        match Model_picker.state t.model_picker with
        | Idle -> act t Refresh_models
        | Loading | Models _ | Error _ -> ())
  | Close_models -> t.model_target <- None
  | Refresh_models when t.model_target = None -> ()
  | Refresh_models ->
      let fetch =
        match t.live_config with
        | Some config -> (
            match Live_runner.gateway config with
            | Some gateway ->
                fun () ->
                  Gateway_models.fetch ~curl:"/usr/bin/curl" ~lookup:Sys.getenv_opt
                    gateway
            | None -> fun () -> Error "Model discovery requires --gateway PATH on launch."
            )
        | None ->
            fun () -> Error "Model discovery requires live mode with an explicit gateway."
      in
      Model_picker.refresh t.model_picker fetch
  | Choose_model model -> (
      match t.model_target with
      | Some (Workspace_model form)
        when Option.fold ~none:false
               ~some:(fun current -> current == form)
               t.workspace_form
             && t.creation_job = None && t.creation_request = None
             && List.mem model (Model_picker.visible t.model_picker) -> (
          match Workspace_form.set_model form model with
          | Ok () ->
              t.model_target <- None;
              Workspace_form.report form
                "Model selected for this form. Ctrl-S creates; no run starts."
          | Error error -> Workspace_form.report form error)
      | Some (Task_model id)
        when id = t.selected && List.mem model (Model_picker.visible t.model_picker) -> (
          match selected t with
          | Some task -> (
              match set_model task model with
              | Ok task ->
                  replace t task;
                  t.model_target <- None;
                  if not (String.starts_with ~prefix:"Storage error:" t.status) then
                    t.status <-
                      "Next-run model selected. Compatibility is unverified; no run \
                       starts."
              | Error error -> t.status <- error)
          | None -> ())
      | _ -> ())
  | Open_review -> (
      match selected t with
      | None -> t.status <- "Select a workspace task to review."
      | Some task -> (
          match Review.create task ~jj:t.jj_executable with
          | Error error -> t.status <- error
          | Ok review ->
              t.review <- Some review;
              t.input <- Normal;
              t.help <- false))
  | Refresh_review -> Option.iter Review.refresh t.review
  | Edit_review_executable -> Option.iter Review.edit_executable t.review
  | Next_review_file -> Option.iter (fun review -> Review.jump_file review `Next) t.review
  | Previous_review_file ->
      Option.iter (fun review -> Review.jump_file review `Previous) t.review
  | Close_review -> (
      match t.review with
      | None -> ()
      | Some review when Review.state review = Changes.Loading ->
          t.status <- "Changes refresh is running; wait for bounded completion."
      | Some review ->
          t.jj_executable <- Review.executable review;
          Review.close review;
          t.review <- None)
  | Begin_workspace ->
      if t.database_path = None then
        t.status <-
          "Workspace tasks require persistent storage. Configure TOML or --database \
           first."
      else if t.external_events then
        t.status <- "Workspace creation is unavailable in replay mode."
      else
        let previous =
          List.find_opt (fun (task : task) -> task.workspace <> None) (List.rev t.tasks)
        in
        let source, parent, revision, model =
          match previous with
          | None -> ("", "", "@", if t.live_config <> None then "" else "coding-large")
          | Some task ->
              let w = Option.get task.workspace in
              (w.source, Filename.dirname w.directory, w.base, task.model)
        in
        let defaults = t.workspace_defaults in
        let source =
          Option.value
            ~default:
              (if defaults.mode = Workspace_defaults.Folder then Sys.getcwd () else source)
            defaults.source
        and parent = Option.value ~default:parent defaults.parent
        and revision = Option.value ~default:revision defaults.revision
        and model = Option.value ~default:model defaults.model in
        let jj =
          if t.jj_executable <> "" then t.jj_executable
          else
            Option.value
              ~default:(Option.value ~default:"" (Executable_path.resolve "jj"))
              defaults.jj
        in
        t.workspace_form <-
          Some (Workspace_form.create ~jj ~source ~parent ~revision ~model ());
        Option.iter
          (fun form ->
            match defaults.mode with
            | Workspace_defaults.Existing -> ()
            | Folder -> Workspace_form.toggle_folder_root form
            | Greenfield -> Workspace_form.toggle_greenfield form)
          t.workspace_form;
        t.help <- false;
        t.input <- Normal;
        t.status <-
          "Explicit creation only. jj can snapshot source files; no agent starts."
  | Workspace_field field ->
      Option.iter (fun form -> Workspace_form.focus form field) t.workspace_form
  | Cancel_workspace ->
      if t.creation_job = None && t.creation_request = None then t.workspace_form <- None
      else
        report_creation t
          "Creation is in progress. Wait for its bounded completion before closing."
  | Send_workspace ->
      act t Submit_workspace;
      t.creation_send <- t.creation_request <> None
  | Submit_workspace ->
      if t.creation_request <> None || t.creation_job <> None then ()
      else (
        t.creation_send <- false;
        match t.workspace_form with
        | None -> ()
        | Some form -> (
            match Workspace_form.validate_submission form with
            | Error error -> report_creation t error
            | Ok () ->
                let value = Workspace_form.value form in
                let id = next_id t "T" in
                t.creation_request <-
                  Some
                    {
                      Task_creation.id;
                      greenfield = Workspace_form.greenfield form;
                      folder_root = Workspace_form.folder_root form;
                      jj = value Workspace_form.Jj;
                      source = value Workspace_form.Source;
                      parent = value Workspace_form.Parent;
                      revision = value Workspace_form.Revision;
                      model = value Workspace_form.Model;
                      instruction = value Workspace_form.Task;
                    };
                Workspace_form.report form "Creating workspace. No agent starts."))
  | Begin_new when t.live_config <> None -> act t Begin_workspace
  | Begin_new ->
      t.input <- New_task;
      t.new_title <- "";
      t.editor <- Text_edit.create ""
  | Toggle_pause ->
      if t.live_config <> None then
        t.status <- "Live updates cannot be paused; use x to stop."
      else if t.fake_harness then
        t.status <- "Process fixture updates cannot be paused. Use x to stop."
      else if t.external_events then
        t.status <- "Replay input stays live. Pause is available for the demo only."
      else (
        t.paused <- not t.paused;
        if not t.paused then
          t.schedules <-
            List.mapi
              (fun i (_, e) -> (Unix.gettimeofday () +. (float_of_int i *. 0.5), e))
              t.schedules)
  | Toggle_archive -> if t.archive then act t Session_board else act t Archive_view
  | Start -> (
      if t.live_config <> None then
        match selected t with
        | None -> ()
        | Some task -> (
            match Live_runner.prepare (Option.get t.live_config) task with
            | Error error -> t.status <- error
            | Ok _ -> (
                match
                  Model.start ~simulated:false
                    ~policy:(Live_runner.policy (Option.get t.live_config))
                    task (next_id t "live-run")
                with
                | Error error -> t.status <- error
                | Ok task ->
                    replace t task;
                    t.status <- "Sending to Codex. Waiting for the durable checkpoint."))
      else if t.external_events then
        t.status <- "Replay mode cannot start runs. Use a fixture run ID."
      else
        match selected t with
        | None -> ()
        | Some task -> (
            let run_id = next_id t "demo-run" in
            match start task run_id with
            | Error error -> t.status <- error
            | Ok task ->
                replace t task;
                if not t.fake_harness then
                  t.schedules <-
                    t.schedules
                    @ List.map
                        (fun (delay, e) -> (Unix.gettimeofday () +. delay, e))
                        (Demo.Seed.schedule task.id run_id);
                t.status <-
                  (if t.fake_harness then
                     "Local fake harness queued. No Codex or model call."
                   else "Simulated run started. Cards follow lifecycle events.")))
  | Stop -> (
      match selected t with
      | Some { active = Some run; id; _ } ->
          receive t { task_id = id; run_id = run.id; event = Interrupted };
          t.status <-
            (if t.live_config <> None then
               "Live cancellation requested. Stale updates are ignored."
             else "Simulated run interrupted. Stale updates are ignored.")
      | _ -> t.status <- "There is no active run to stop.")
  | Restore_task -> (
      match selected t with
      | None -> ()
      | Some task -> (
          match Model.restore task with
          | Error error -> t.status <- error
          | Ok task ->
              replace t task;
              act t Session_board;
              if not (String.starts_with ~prefix:"Storage error:" t.status) then
                t.status <-
                  "Task restored to Ready. History and pending replies retained; no run \
                   starts."))
  | Accept -> (
      match selected t with
      | None -> ()
      | Some task -> (
          match accept task with
          | Error error -> t.status <- error
          | Ok task ->
              replace t task;
              if not (String.starts_with ~prefix:"Storage error:" t.status) then
                t.status <-
                  Acceptance_summary.status
                    (Acceptance_summary.make ~draft:(draft t) task)))

let append_utf8 buffer uchar = Uutf.Buffer.add_utf_8 buffer uchar

let clean ?(newlines = true) text =
  if newlines then Terminal_text.multiline text else Terminal_text.line text

let remove_last text =
  let last = ref 0 in
  Uutf.String.fold_utf_8 (fun () i _ -> last := i) () text;
  String.sub text 0 !last

let reject_input t limit =
  t.input_limit <- Some limit;
  if not (String.starts_with ~prefix:"Storage error:" t.status) then
    t.status <-
      (if limit = 256 then "Chat search is limited to 256 bytes."
       else "Input is limited to 64 KiB. The edit was not applied.")

let accept_input t editor =
  let text = Text_edit.text editor in
  let limit = if t.input = Chat_search then 256 else 65536 in
  if String.length text > limit then (
    reject_input t limit;
    false)
  else (
    if Text_edit.text editor <> Text_edit.text t.editor then (
      t.input_limit <- None;
      t.input_error <- None);
    t.editor <- editor;
    (match t.input with
    | Search ->
        t.query <- text;
        t.board_scroll <- 0;
        repair_selection t
    | Chat_search ->
        Chat_search.set_query t.chat_search text;
        Option.iter
          (fun (task : task) -> Chat_search.sync t.chat_search task.messages)
          (selected t)
    | Compose -> set_draft t text
    | Edit_model -> t.model_text <- text
    | New_task -> t.new_title <- text
    | Normal -> ());
    true)

let set_input t text = ignore (accept_input t (Text_edit.create text))
let edit t fn = ignore (accept_input t (fn t.editor))

let insert_text t value =
  if t.input <> Normal then
    let value = clean ~newlines:(t.input = Compose) value in
    let editor = Text_edit.insert t.editor value in
    if value <> "" && editor == t.editor then reject_input t 65536
    else ignore (accept_input t editor)

let paste_key t (key, mods) =
  if t.deletion <> None then
    match key with
    | `ASCII char -> Task_deletion.insert (Option.get t.deletion) (String.make 1 char)
    | _ -> ()
  else if t.project_picker <> None then
    let picker = Option.get t.project_picker in
    match key with
    | `ASCII char -> Project_picker.insert picker (String.make 1 char)
    | `Uchar char ->
        let buffer = Buffer.create 4 in
        Uutf.Buffer.add_utf_8 buffer char;
        Project_picker.insert picker (Buffer.contents buffer)
    | _ -> ()
  else if t.model_target <> None then
    match key with
    | `ASCII char -> Model_picker.insert t.model_picker (String.make 1 char)
    | `Uchar char ->
        let buffer = Buffer.create 4 in
        Uutf.Buffer.add_utf_8 buffer char;
        Model_picker.insert t.model_picker (Buffer.contents buffer)
    | _ -> ()
  else if t.review <> None then Review.paste_key (Option.get t.review) (key, mods)
  else if t.workspace_form <> None then (
    if t.creation_job = None && t.creation_request = None then
      Workspace_form.paste_key (Option.get t.workspace_form) (key, []))
  else if t.input <> Normal then
    match key with
    | `Enter -> if t.input = Compose then insert_text t "\n" else insert_text t " "
    | `ASCII char -> insert_text t (String.make 1 char)
    | `Uchar uchar ->
        let buffer = Buffer.create 4 in
        append_utf8 buffer uchar;
        insert_text t (Buffer.contents buffer)
    | _ -> ()

let input_failure t error =
  t.input_error <- Some error;
  if not (String.starts_with ~prefix:"Storage error:" t.status) then t.status <- error

let submission_success t message =
  t.input_error <- None;
  t.input_limit <- None;
  if not (String.starts_with ~prefix:"Storage error:" t.status) then t.status <- message

let submit t =
  match t.input with
  | Normal | Search | Chat_search -> t.input <- Normal
  | Compose -> (
      match selected t with
      | None -> t.input <- Normal
      | Some task -> (
          match send task ~id:(next_id t "message") (draft t) with
          | Error error -> input_failure t error
          | Ok task ->
              replace t task;
              set_draft t "";
              t.input <- Normal;
              act t Follow_chat;
              submission_success t
                (if t.live_config <> None then
                   "Reply sent. It waits for the next turn while the current run is \
                    active."
                 else "Reply queued for the next run. No live agent receives it.");
              if
                t.live_config <> None && task.state <> Working
                && not (String.starts_with ~prefix:"Storage error:" t.status)
              then act t Start))
  | Edit_model -> (
      match selected t with
      | None -> t.input <- Normal
      | Some task -> (
          match set_model task t.model_text with
          | Error error -> input_failure t error
          | Ok task ->
              replace t task;
              t.input <- Normal;
              submission_success t
                "Next-run model updated. Gateway compatibility is unverified."))
  | New_task ->
      let title = String.trim t.new_title in
      if title <> "" then (
        let id = next_id t "T" in
        t.tasks <- t.tasks @ [ make ~id ~title ~repository:"factory-tui" ];
        t.archive <- false;
        t.repository <- None;
        t.query <- "";
        select t id;
        t.input <- Normal;
        submission_success t "Task created in memory. Start runs a simulated fixture.")
      else input_failure t "Enter a task instruction before creating a task."

let navigation_tasks t =
  Board_navigation.vertical
    ~columns:((not t.archive) && not t.board_list)
    ~selected:t.selected (visible t)

let move_in t tasks delta =
  Option.iter (select t) (Board_navigation.move ~selected:t.selected ~delta tasks)

let scroll t delta =
  let delta = if t.focus = Activity then delta else -delta in
  t.scroll <- max 0 (min 1_000_000 (t.scroll + delta))

let navigate t direction =
  match direction with
  | `Up | `Down ->
      let delta = if direction = `Up then -1 else 1 in
      if t.focus <> Board || t.zoom then scroll t delta
      else move_in t (navigation_tasks t) delta
  | `Left | `Right ->
      if t.focus <> Board || t.zoom then ()
      else if t.archive || t.board_list then
        move_in t (navigation_tasks t) (if direction = `Left then -1 else 1)
      else
        Option.iter (select t)
          (Board_navigation.horizontal ~right:(direction = `Right) ~selected:t.selected
             (visible t))

let edge t last =
  if t.focus = Board && not t.zoom then
    Option.iter (select t) (Board_navigation.edge ~last (navigation_tasks t))
  else if t.focus = Activity then t.scroll <- (if last then 1_000_000 else 0)
  else t.scroll <- (if last then 0 else 1_000_000)

let page t delta =
  if t.focus = Board && not t.zoom then move_in t (navigation_tasks t) delta
  else scroll t delta

let cycle_focus t backwards =
  let focus =
    match (t.focus, backwards) with
    | Board, false | Activity, true -> Conversation
    | Conversation, false | Board, true -> Activity
    | Activity, false | Conversation, true -> Board
  in
  let focus =
    if t.zoom && focus = Board then if backwards then Activity else Conversation
    else focus
  in
  focus_pane t focus;
  reset_chat_view t;
  t.scroll <- 0

let window_focus t direction =
  let focus =
    match direction with
    | `Left ->
        if t.focus = Activity then Conversation
        else if t.zoom then Conversation
        else Board
    | `Right -> if t.focus = Board then Conversation else Activity
    | `Up -> if t.zoom then Conversation else Board
    | `Down -> if t.focus = Board then Conversation else Activity
  in
  focus_pane t focus;
  reset_chat_view t;
  t.scroll <- 0

let repeat count fn =
  for _ = 1 to count do
    fn ()
  done

let resize_panes t delta =
  let result = Pane_layout.resize t.pane_layout ~detail:(t.focus <> Board) ~delta in
  if not (contains t.status "Storage error:") then
    t.status <-
      (match result with
      | Pane_layout.Changed -> "Pane split adjusted. Ctrl-W = restores startup sizes."
      | Pane_layout.At_limit -> "Pane size limit keeps both regions usable."
      | Pane_layout.No_split ->
          if t.zoom then "No board/chat split is visible. Return from zoom with Esc."
          else
            "No board/chat split is visible. Enlarge the terminal to show both regions.")

let normal_key t (key, mods) =
  let count = max 1 t.count in
  let prefix = t.prefix in
  let command fn =
    reset_keys t;
    fn ()
  in
  if List.mem `Ctrl mods then
    command (fun () ->
        match key with
        | `ASCII 'a' when prefix <> Window -> act t Accept
        | `ASCII 'x' when prefix <> Window -> act t Begin_delete
        | `ASCII 'w' ->
            if prefix = Window then cycle_focus t false
            else (
              t.prefix <- Window;
              t.count <- (if count = 1 then 0 else count))
        | `ASCII 'h' when prefix = Window -> window_focus t `Left
        | `ASCII 'j' when prefix = Window -> window_focus t `Down
        | `ASCII 'k' when prefix = Window -> window_focus t `Up
        | `ASCII 'l' when prefix = Window -> window_focus t `Right
        | `ASCII 'u' -> page t (-count * max 1 (t.page_rows / 2))
        | `ASCII 'd' -> page t (count * max 1 (t.page_rows / 2))
        | `ASCII 'b' -> page t (-count * t.page_rows)
        | `ASCII 'f' -> page t (count * t.page_rows)
        | _ -> ())
  else if key = `Tab then command (fun () -> cycle_focus t (List.mem `Shift mods))
  else if mods <> [] && mods <> [ `Shift ] then reset_keys t
  else if prefix = Window then
    command (fun () ->
        match key with
        | `ASCII 'h' | `Arrow `Left -> window_focus t `Left
        | `ASCII 'j' | `Arrow `Down -> window_focus t `Down
        | `ASCII 'k' | `Arrow `Up -> window_focus t `Up
        | `ASCII 'l' | `Arrow `Right -> window_focus t `Right
        | `ASCII 'w' -> cycle_focus t false
        | `ASCII '+' -> resize_panes t count
        | `ASCII '-' -> resize_panes t (-count)
        | `ASCII '=' ->
            Pane_layout.reset t.pane_layout;
            if not (contains t.status "Storage error:") then
              t.status <-
                (if Pane_layout.defaults t.pane_layout = Pane_layout.automatic then
                   "Automatic pane sizes restored."
                 else "Configured pane sizes restored.")
        | _ -> ())
  else if prefix = Go && key = `ASCII 'g' then command (fun () -> edge t false)
  else (
    t.prefix <- No_prefix;
    match key with
    | `ASCII ('0' .. '9' as digit) ->
        if digit <> '0' || t.count <> 0 then
          t.count <- min 999 ((t.count * 10) + Char.code digit - Char.code '0')
    | `ASCII 'g' -> t.prefix <- Go
    | `ASCII 'G' -> command (fun () -> edge t true)
    | `ASCII 'q' -> command (fun () -> act t Quit)
    | `ASCII '?' | `Function 1 -> command (fun () -> act t Help)
    | `ASCII 'e' -> command (fun () -> act t Zoom)
    | `Enter ->
        command (fun () ->
            act t
              (match t.focus with
              | Board -> Open_conversation
              | Conversation -> Begin_compose
              | Activity -> Zoom))
    | `Escape -> command (fun () -> act t Back)
    | `ASCII '/' ->
        command (fun () ->
            act t (if t.focus = Conversation then Begin_chat_search else Begin_search))
    | `ASCII 'S' -> command (fun () -> act t Begin_chat_search)
    | `ASCII 'N' when Chat_search.query t.chat_search <> "" && t.focus = Conversation ->
        command (fun () -> act t Previous_chat_match)
    | `ASCII 'i' -> command (fun () -> act t Begin_compose)
    | `ASCII 'R' -> command (fun () -> act t Next_repository)
    | `ASCII 'b' -> command (fun () -> act t Session_board)
    | `ASCII 'T' -> command (fun () -> act t Toggle_raw_tools)
    | `ASCII 't' -> command (fun () -> act t Toggle_tools)
    | `ASCII 'M' -> command (fun () -> act t Open_models)
    | `ASCII 'm' -> command (fun () -> act t Begin_model)
    | `ASCII 'H' -> command (fun () -> act t Next_harness)
    | `ASCII 'v' -> command (fun () -> act t Open_review)
    | `ASCII 'W' -> command (fun () -> act t Begin_workspace)
    | `ASCII 'n' when Chat_search.query t.chat_search <> "" && t.focus = Conversation ->
        command (fun () -> act t Next_chat_match)
    | `ASCII 'n' -> command (fun () -> act t Begin_new)
    | `ASCII 's' | `Function 5 -> command (fun () -> act t Start)
    | `ASCII 'x' | `Function 6 -> command (fun () -> act t Stop)
    | `ASCII 'a' ->
        command (fun () ->
            t.status <-
              "Use Ctrl-A to accept and archive Ready work; u restores archived work.")
    | `ASCII 'u' -> command (fun () -> act t Restore_task)
    | `ASCII 'f' -> command (fun () -> act t Toggle_pause)
    | `ASCII 'j' | `Arrow `Down ->
        command (fun () -> repeat count (fun () -> navigate t `Down))
    | `ASCII 'k' | `Arrow `Up ->
        command (fun () -> repeat count (fun () -> navigate t `Up))
    | `ASCII 'h' | `Arrow `Left ->
        command (fun () -> repeat count (fun () -> navigate t `Left))
    | `ASCII 'l' | `Arrow `Right ->
        command (fun () -> repeat count (fun () -> navigate t `Right))
    | `Page `Up -> command (fun () -> page t (-count * t.page_rows))
    | `Page `Down -> command (fun () -> page t (count * t.page_rows))
    | `Home -> command (fun () -> edge t false)
    | `End -> command (fun () -> edge t true)
    | _ -> reset_keys t)

let key t (key, mods) =
  (* Terminal input maps Ctrl letters to uppercase ASCII. *)
  let key =
    match key with
    | `ASCII char when List.mem `Ctrl mods -> `ASCII (Char.lowercase_ascii char)
    | key -> key
  in
  if key = `ASCII 'c' && List.mem `Ctrl mods then (
    reset_keys t;
    t.quit <- true)
  else if t.deletion <> None then (
    reset_keys t;
    match Task_deletion.key (Option.get t.deletion) (key, mods) with
    | Cancel -> act t Cancel_delete
    | Confirm -> act t Confirm_delete
    | Edit -> ())
  else if t.project_picker <> None then
    let picker = Option.get t.project_picker in
    match key with
    | `Escape -> act t Close_projects
    | `Enter when mods = [] ->
        Option.iter
          (fun (project : Project.t) -> act t (Choose_project project.name))
          (Project_picker.selected picker)
    | _ -> Project_picker.key picker (key, mods)
  else if t.model_target <> None then (
    reset_keys t;
    match key with
    | `Escape -> act t Close_models
    | `Enter when mods = [] ->
        Option.iter
          (fun id -> act t (Choose_model id))
          (Model_picker.selected t.model_picker)
    | `ASCII 'r' when List.mem `Ctrl mods -> act t Refresh_models
    | _ -> Model_picker.key t.model_picker (key, mods))
  else if t.review <> None then (
    reset_keys t;
    match key with
    | `Escape -> act t Close_review
    | _ -> Review.key (Option.get t.review) (key, mods))
  else if t.workspace_form <> None then (
    reset_keys t;
    if t.creation_job <> None || t.creation_request <> None then ()
    else
      match key with
      | `Escape -> act t Cancel_workspace
      | `ASCII 'e' when List.mem `Ctrl mods -> act t Toggle_folder_root
      | `ASCII 'n' when List.mem `Ctrl mods -> act t Toggle_greenfield
      | `ASCII 'p' when List.mem `Ctrl mods -> act t Open_projects
      | `ASCII 'g' when List.mem `Ctrl mods -> act t Open_models
      | `Enter when mods = [] -> act t Send_workspace
      | `ASCII 's' when List.mem `Ctrl mods -> act t Submit_workspace
      | _ -> Workspace_form.key (Option.get t.workspace_form) (key, mods))
  else if t.help then (
    reset_keys t;
    match key with
    | `Escape | `ASCII '?' -> act t Close_menu
    | `Tab | `ASCII 'h' | `ASCII 'l' | `Arrow `Left | `Arrow `Right ->
        act t
          (Menu_tab
             (match t.menu_tab with Help_tab -> Settings_tab | Settings_tab -> Help_tab))
    | `ASCII 'j' | `Arrow `Down -> t.menu_scroll <- min 10000 (t.menu_scroll + 1)
    | `ASCII 'k' | `Arrow `Up -> t.menu_scroll <- max 0 (t.menu_scroll - 1)
    | `ASCII 'g' | `Home -> t.menu_scroll <- 0
    | `ASCII 'G' | `End -> t.menu_scroll <- 10000
    | `Page `Down -> t.menu_scroll <- min 10000 (t.menu_scroll + t.menu_page_rows)
    | `Page `Up -> t.menu_scroll <- max 0 (t.menu_scroll - t.menu_page_rows)
    | `ASCII 'M' when t.menu_tab = Settings_tab -> act t Open_models
    | `ASCII 'm' when t.menu_tab = Settings_tab ->
        t.help <- false;
        act t Begin_model
    | `ASCII 'H' when t.menu_tab = Settings_tab -> act t Next_harness
    | _ -> ())
  else if key = `ASCII 'x' && List.mem `Ctrl mods && t.input = Compose then
    act t Begin_delete
  else if key = `Tab && t.input = Compose then (
    t.input <- Normal;
    cycle_focus t (List.mem `Shift mods))
  else if t.input <> Normal then (
    reset_keys t;
    match key with
    | `Escape when t.input = Chat_search ->
        Chat_search.clear t.chat_search;
        t.input <- Normal
    | `Escape -> t.input <- Normal
    | `Enter when t.input = Compose && List.mem `Meta mods -> insert_text t "\n"
    | `ASCII 'l' when t.input = Compose && List.mem `Ctrl mods -> insert_text t "\n"
    | `Enter -> submit t
    | `Backspace -> edit t Text_edit.backspace
    | `Delete -> edit t Text_edit.delete
    | `Arrow `Left -> edit t Text_edit.left
    | `Arrow `Right -> edit t Text_edit.right
    | `Arrow `Up when t.input = Compose -> edit t Text_edit.up
    | `Arrow `Down when t.input = Compose -> edit t Text_edit.down
    | `Home -> edit t Text_edit.home
    | `End -> edit t Text_edit.ending
    | `ASCII char when mods = [] || mods = [ `Shift ] ->
        insert_text t (String.make 1 char)
    | `Uchar uchar when mods = [] || mods = [ `Shift ] ->
        let buffer = Buffer.create 4 in
        append_utf8 buffer uchar;
        insert_text t (Buffer.contents buffer)
    | _ -> ())
  else normal_key t (key, mods)

let demo_context t : Demo.Runner.context =
  {
    tasks = (fun () -> t.tasks);
    snapshot = (fun () -> snapshot t);
    pending_events = (fun () -> t.storage_events);
    acknowledge_events = (fun () -> t.storage_events <- []);
    receive = receive t;
    report_error = (fun error -> t.status <- error);
    enabled = (fun () -> t.fake_harness);
    quitting = (fun () -> t.quit);
  }

let poll_creation t ~storage =
  (match t.creation_request with
  | None -> ()
  | Some request -> (
      t.creation_request <- None;
      t.jj_executable <- request.jj;
      match storage with
      | None -> report_creation t "Persistent storage is required for workspace creation."
      | Some worker -> (
          match Persistence.error worker with
          | Some error -> report_creation t ("Storage error: " ^ error)
          | None -> t.creation_job <- Some (Task_creation.start request))));
  match t.creation_job with
  | None -> ()
  | Some job -> (
      match Task_creation.result job with
      | None -> ()
      | Some result -> (
          Task_creation.close job;
          t.creation_job <- None;
          match result with
          | Error error ->
              t.creation_send <- false;
              report_creation t error
          | Ok task ->
              t.tasks <- t.tasks @ [ task ];
              select t task.id;
              t.archive <- false;
              t.repository <- None;
              t.query <- "";
              t.workspace_form <- None;
              focus_pane t Conversation;
              t.status <-
                "Workspace task created / Queued (not started). Press s to review and \
                 start the run.";
              let send = t.creation_send in
              t.creation_send <- false;
              if send && (not t.quit) && t.live_config <> None then act t Start))

let finish_creation t ~storage =
  t.creation_request <- None;
  Option.iter Task_creation.close t.creation_job;
  poll_creation t ~storage

let enable_live t config =
  if t.database_path = None then Error "Live UI requires configured SQLite storage."
  else if t.fake_harness || t.external_events then
    Error "Live UI cannot use demo processes or replay."
  else (
    t.live_config <- Some config;
    t.schedules <- [];
    t.tasks <- (Snapshot.recover (snapshot t)).tasks;
    t.status <- "Live UI enabled / no process started. Enter sends work; x stops.";
    Ok ())

let live_context t : Live_runner.context =
  {
    tasks = (fun () -> t.tasks);
    snapshot = (fun () -> snapshot t);
    pending_events = (fun () -> t.storage_events);
    acknowledge_events = (fun () -> t.storage_events <- []);
    receive = receive t;
    report_error = (fun error -> t.status <- "Live error: " ^ error);
    quitting = (fun () -> t.quit);
  }

let set_workspace_defaults t defaults =
  t.workspace_defaults <- defaults;
  t.jj_executable <- Option.value ~default:t.jj_executable defaults.Workspace_defaults.jj

let initialize_board t ~saved ~live =
  (match saved with
  | Some saved -> restore t saved
  | None when live <> None ->
      t.tasks <- [];
      t.drafts <- [];
      t.selected <- "";
      t.schedules <- [];
      Chat_search.clear t.chat_search;
      Chat_viewport.reset t.chat_viewport
  | None -> ());
  match live with None -> Ok () | Some config -> enable_live t config
