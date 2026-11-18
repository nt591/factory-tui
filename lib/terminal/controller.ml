open Model

type focus = Board | Conversation | Activity
type input = Normal | Search | Chat_search | Compose | New_task | Edit_model
type menu_tab = Help_tab | Settings_tab
type prefix = No_prefix | Go | Window

type action =
  | Select of string
  | Zoom
  | Focus of focus
  | Start
  | Stop
  | Accept
  | Repository of string option
  | Session_board
  | Archive_view
  | Menu_tab of menu_tab
  | Close_menu
  | Toggle_tools
  | Next_repository
  | Next_harness
  | Begin_model
  | Toggle_archive
  | Toggle_pause
  | Help
  | Quit
  | Begin_chat_search
  | Next_chat_match
  | Previous_chat_match
  | Clear_chat_search
  | Begin_search
  | Begin_compose
  | Confirm_live
  | Cancel_live
  | Open_review
  | Refresh_review
  | Edit_review_executable
  | Close_review
  | Begin_workspace
  | Submit_workspace
  | Cancel_workspace
  | Workspace_field of Workspace_form.field
  | Begin_new

type t = {
  mutable live_config : Live_runner.config option;
  mutable live_confirmation : string option;
  mutable confirmation_readable : bool;
  mutable review : Review.t option;
  mutable jj_executable : string;
  mutable workspace_defaults : Workspace_defaults.t;
  mutable workspace_form : Workspace_form.t option;
  mutable creation_job : Task_creation.job option;
  mutable creation_request : Task_creation.request option;
  mutable tasks : task list;
  mutable selected : string;
  mutable focus : focus;
  mutable zoom : bool;
  mutable archive : bool;
  mutable paused : bool;
  mutable help : bool;
  mutable menu_tab : menu_tab;
  mutable menu_scroll : int;
  mutable repository : string option;
  mutable tools_expanded : bool;
  mutable database_path : string option;
  mutable input : input;
  mutable query : string;
  chat_search : Chat_search.t;
  chat_viewport : Chat_viewport.t;
  mutable new_title : string;
  mutable model_text : string;
  mutable editor : Text_edit.t;
  mutable drafts : (string * string) list;
  mutable scroll : int;
  mutable board_scroll : int;
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
    live_config = None;
    live_confirmation = None;
    confirmation_readable = true;
    review = None;
    jj_executable = "";
    workspace_defaults = Workspace_defaults.empty;
    workspace_form = None;
    creation_job = None;
    creation_request = None;
    tasks =
      (if fake_harness then
         (Snapshot.recover
            { tasks = Demo.Seed.seed (); drafts = []; selected = "T-102"; serial = 200 })
           .tasks
       else Demo.Seed.seed ());
    selected = "T-102";
    focus = Board;
    zoom = false;
    archive = false;
    paused = false;
    help = false;
    menu_tab = Help_tab;
    menu_scroll = 0;
    repository = None;
    tools_expanded = false;
    database_path = None;
    input = Normal;
    query = "";
    chat_search = Chat_search.create ();
    chat_viewport = Chat_viewport.create ();
    new_title = "";
    model_text = "";
    editor = Text_edit.create "";
    drafts = [];
    scroll = 0;
    board_scroll = 0;
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

let contains text query =
  let text = String.lowercase_ascii text and query = String.lowercase_ascii query in
  let rec loop i =
    i + String.length query <= String.length text
    && (String.sub text i (String.length query) = query || loop (i + 1))
  in
  loop 0

let visible t =
  List.filter
    (fun (task : task) ->
      (if t.archive then task.state = Done else task.state <> Done)
      && (match t.repository with
        | None -> true
        | Some repository -> task.repository = repository)
      && contains (task.id ^ " " ^ task.title ^ " " ^ task.repository) t.query)
    t.tasks

let repositories t =
  List.map (fun (task : task) -> task.repository) t.tasks |> List.sort_uniq String.compare

let selected t = List.find_opt (fun (task : task) -> task.id = t.selected) t.tasks
let draft t = Option.value ~default:"" (List.assoc_opt t.selected t.drafts)

let set_draft t text =
  t.drafts <- (t.selected, text) :: List.remove_assoc t.selected t.drafts

let next_id t prefix =
  t.serial <- t.serial + 1;
  Printf.sprintf "%s-%d" prefix t.serial

let replace t (task : task) =
  t.tasks <- List.map (fun (old : task) -> if old.id = task.id then task else old) t.tasks

let result t = function Ok task -> replace t task | Error error -> t.status <- error

let reset_keys t =
  t.prefix <- No_prefix;
  t.count <- 0

let select t id =
  if t.selected <> id then Chat_search.clear t.chat_search;
  t.selected <- id;
  Chat_viewport.reset t.chat_viewport;
  t.scroll <- 0;
  t.board_scroll <- 0

let repair_selection t =
  if not (List.exists (fun (task : task) -> task.id = t.selected) (visible t)) then
    match visible t with task :: _ -> select t task.id | [] -> t.selected <- ""

let receive t event =
  let tasks = reduce t.tasks event in
  if tasks <> t.tasks && t.retain_events then
    t.storage_events <- t.storage_events @ [ event ];
  t.tasks <- tasks

let snapshot t : Snapshot.t =
  { tasks = t.tasks; drafts = t.drafts; selected = t.selected; serial = t.serial }

let restore t saved =
  let saved = Snapshot.recover saved in
  t.tasks <- saved.tasks;
  t.drafts <- saved.drafts;
  t.selected <- saved.selected;
  t.serial <- saved.serial;
  t.schedules <- [];
  repair_selection t;
  t.status <- "Saved conversations restored. Interrupted runs need your input."

let tick t now =
  if not t.paused then (
    let due, later = List.partition (fun (time, _) -> time <= now) t.schedules in
    t.schedules <- later;
    List.iter (fun (_, event) -> receive t event) due)

let act t action =
  reset_keys t;
  match action with
  | Select id ->
      select t id;
      t.focus <- Board
  | Focus focus -> t.focus <- focus
  | Zoom ->
      t.zoom <- not t.zoom;
      t.focus <- Conversation;
      Chat_viewport.reset t.chat_viewport;
      t.scroll <- 0
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
  | Toggle_tools -> t.tools_expanded <- not t.tools_expanded
  | Repository repository ->
      t.repository <- repository;
      t.board_scroll <- 0;
      t.focus <- Board
  | Archive_view ->
      t.archive <- true;
      t.board_scroll <- 0;
      t.focus <- Board
  | Session_board ->
      t.archive <- false;
      t.repository <- None;
      t.board_scroll <- 0;
      t.focus <- Board
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
      t.board_scroll <- 0;
      t.focus <- Board
  | Begin_chat_search -> (
      match selected t with
      | None -> ()
      | Some _ ->
          t.input <- Chat_search;
          t.focus <- Conversation;
          t.editor <- Text_edit.create (Chat_search.query t.chat_search))
  | Next_chat_match | Previous_chat_match ->
      Option.iter
        (fun (task : task) -> Chat_search.sync t.chat_search task.messages)
        (selected t);
      Chat_search.move t.chat_search ~backwards:(action = Previous_chat_match);
      t.focus <- Conversation
  | Clear_chat_search -> Chat_search.clear t.chat_search
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
          t.focus <- Conversation)
  | Next_harness -> (
      match selected t with
      | None -> ()
      | Some task -> (
          match
            set_harness task (match task.harness with Codex -> Claude | Claude -> Codex)
          with
          | Error error -> t.status <- error
          | Ok task ->
              replace t task;
              t.status <- "Next-run harness selection only. No agent starts."))
  | Begin_model -> (
      match selected t with
      | None -> ()
      | Some task ->
          t.model_text <- task.model;
          t.input <- Edit_model;
          t.editor <- Text_edit.create task.model)
  | Cancel_live -> t.live_confirmation <- None
  | Confirm_live when not t.confirmation_readable ->
      t.status <- "Resize the terminal before confirming a live run."
  | Confirm_live -> (
      match (t.live_confirmation, t.live_config) with
      | Some id, Some config -> (
          t.live_confirmation <- None;
          match List.find_opt (fun (task : task) -> task.id = id) t.tasks with
          | None -> t.status <- "Confirmed task no longer exists."
          | Some task -> (
              match Live_runner.prepare config task with
              | Error error -> t.status <- error
              | Ok _ -> (
                  match
                    Model.start ~simulated:false ~policy:(Live_runner.policy config) task
                      (next_id t "live-run")
                  with
                  | Error error -> t.status <- error
                  | Ok task ->
                      replace t task;
                      t.status <-
                        "Live Codex run queued. Waiting for the durable checkpoint.")))
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
          | None -> ("", "", "@", "coding-large")
          | Some task ->
              let w = Option.get task.workspace in
              (w.source, Filename.dirname w.directory, w.base, task.model)
        in
        let defaults = t.workspace_defaults in
        let source = Option.value ~default:source defaults.source
        and parent = Option.value ~default:parent defaults.parent
        and revision = Option.value ~default:revision defaults.revision
        and model = Option.value ~default:model defaults.model in
        let jj =
          if t.jj_executable <> "" then t.jj_executable
          else Option.value ~default:"" defaults.jj
        in
        t.workspace_form <-
          Some (Workspace_form.create ~jj ~source ~parent ~revision ~model ());
        t.help <- false;
        t.input <- Normal;
        t.status <-
          "Explicit creation only. jj can snapshot source files; no agent starts."
  | Workspace_field field ->
      Option.iter (fun form -> Workspace_form.focus form field) t.workspace_form
  | Cancel_workspace ->
      if t.creation_job = None && t.creation_request = None then t.workspace_form <- None
      else
        t.status <-
          "Creation is in progress. Wait for its bounded completion before closing."
  | Submit_workspace -> (
      if t.creation_request <> None || t.creation_job <> None then ()
      else
        match t.workspace_form with
        | None -> ()
        | Some form -> (
            match Workspace_form.validate form with
            | Error error -> t.status <- error
            | Ok () ->
                let value = Workspace_form.value form in
                let id = next_id t "T" in
                t.creation_request <-
                  Some
                    {
                      Task_creation.id;
                      jj = value Workspace_form.Jj;
                      source = value Workspace_form.Source;
                      parent = value Workspace_form.Parent;
                      revision = value Workspace_form.Revision;
                      model = value Workspace_form.Model;
                      instruction = value Workspace_form.Task;
                    }))
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
  | Toggle_archive ->
      t.archive <- not t.archive;
      t.board_scroll <- 0
  | Start -> (
      if t.live_config <> None then
        match selected t with
        | None -> ()
        | Some task -> (
            match Live_runner.prepare (Option.get t.live_config) task with
            | Error error -> t.status <- error
            | Ok _ -> t.live_confirmation <- Some task.id)
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
  | Accept -> ( match selected t with Some task -> result t (accept task) | None -> ())

let append_utf8 buffer uchar = Uutf.Buffer.add_utf_8 buffer uchar

let clean ?(newlines = true) text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> append_utf8 buffer Uutf.u_rep
      | `Uchar u ->
          let n = Uchar.to_int u in
          if n = 10 && newlines then Buffer.add_char buffer '\n'
          else if n < 32 || (n >= 127 && n <= 159) then Buffer.add_char buffer ' '
          else append_utf8 buffer u)
    () text;
  Buffer.contents buffer

let remove_last text =
  let last = ref 0 in
  Uutf.String.fold_utf_8 (fun () i _ -> last := i) () text;
  String.sub text 0 !last

let set_input t text =
  if t.input = Chat_search && String.length text > 256 then
    t.status <- "Chat search is limited to 256 bytes."
  else if String.length text <= 65536 then (
    t.editor <- Text_edit.create text;
    match t.input with
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
    | Normal -> ())

let edit t fn =
  let editor = fn t.editor in
  let text = Text_edit.text editor in
  if t.input = Chat_search && String.length text > 256 then
    t.status <- "Chat search is limited to 256 bytes."
  else (
    set_input t text;
    t.editor <- editor)

let insert_text t value =
  if t.input <> Normal then
    edit t (fun editor ->
        Text_edit.insert editor (clean ~newlines:(t.input = Compose) value))

let paste_key t (key, mods) =
  if t.live_confirmation <> None then ()
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

let submit t =
  match t.input with
  | Normal | Search | Chat_search -> t.input <- Normal
  | Compose -> (
      match selected t with
      | None -> t.input <- Normal
      | Some task -> (
          match send task ~id:(next_id t "message") (draft t) with
          | Error error -> t.status <- error
          | Ok task ->
              replace t task;
              set_draft t "";
              t.input <- Normal;
              t.status <-
                (if t.live_config <> None then
                   "Reply queued for the next confirmed turn; active run is unchanged."
                 else "Reply queued for the next run. No live agent receives it.")))
  | Edit_model -> (
      match selected t with
      | None -> t.input <- Normal
      | Some task -> (
          match set_model task t.model_text with
          | Error error -> t.status <- error
          | Ok task ->
              replace t task;
              t.input <- Normal;
              t.status <- "Next-run model updated. Gateway compatibility is unverified."))
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
        t.status <- "Task created in memory. Start runs a simulated fixture.")

let ordered_tasks t =
  let tasks = visible t in
  if t.archive then tasks
  else
    List.concat_map
      (fun state -> List.filter (fun (task : task) -> task.state = state) tasks)
      columns

let navigation_tasks t =
  let tasks = ordered_tasks t in
  match selected t with
  | Some task when (not t.archive) && List.exists (fun (x : task) -> x.id = task.id) tasks
    ->
      List.filter (fun (x : task) -> x.state = task.state) tasks
  | _ -> tasks

let move_in t tasks delta =
  let rec index i = function
    | [] -> if delta >= 0 then -1 else List.length tasks
    | (task : task) :: _ when task.id = t.selected -> i
    | _ :: rest -> index (i + 1) rest
  in
  if tasks <> [] then
    select t
      (List.nth tasks (max 0 (min (List.length tasks - 1) (index 0 tasks + delta)))).id

let scroll t delta =
  let delta = if t.focus = Activity then delta else -delta in
  t.scroll <- max 0 (min 1_000_000 (t.scroll + delta))

let navigate t direction =
  match direction with
  | `Up | `Down ->
      let delta = if direction = `Up then -1 else 1 in
      if t.focus <> Board || t.zoom then scroll t delta
      else move_in t (navigation_tasks t) delta
  | `Left | `Right -> (
      if t.focus <> Board || t.zoom then ()
      else if t.archive then
        move_in t (ordered_tasks t) (if direction = `Left then -1 else 1)
      else
        match selected t with
        | None -> ()
        | Some task ->
            let states = if direction = `Left then List.rev columns else columns in
            let rec find = function
              | [] -> ()
              | state :: rest when state = task.state -> next rest
              | _ :: rest -> find rest
            and next = function
              | [] -> ()
              | state :: rest -> (
                  match
                    List.find_opt (fun (x : task) -> x.state = state) (ordered_tasks t)
                  with
                  | Some x -> select t x.id
                  | None -> next rest)
            in
            find states)

let edge t last =
  if t.focus = Board && not t.zoom then
    let tasks = navigation_tasks t in
    match if last then List.rev tasks else tasks with
    | task :: _ -> select t task.id
    | [] -> ()
  else if t.focus = Activity then t.scroll <- (if last then 1_000_000 else 0)
  else t.scroll <- (if last then 0 else 1_000_000)

let page t delta =
  if t.focus = Board && not t.zoom then move_in t (navigation_tasks t) delta
  else scroll t delta

let cycle_focus t backwards =
  t.focus <-
    (match (t.focus, backwards) with
    | Board, false | Activity, true -> Conversation
    | Conversation, false | Board, true -> Activity
    | Activity, false | Conversation, true -> Board);
  if t.zoom && t.focus = Board then
    t.focus <- (if backwards then Activity else Conversation);
  Chat_viewport.reset t.chat_viewport;
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
  t.focus <- focus;
  Chat_viewport.reset t.chat_viewport;
  t.scroll <- 0

let repeat count fn =
  for _ = 1 to count do
    fn ()
  done

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
        | `ASCII 'w' ->
            if prefix = Window then cycle_focus t false else t.prefix <- Window
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
    | `ASCII 'e' | `Enter -> command (fun () -> act t Zoom)
    | `Escape ->
        command (fun () ->
            if Chat_search.query t.chat_search <> "" && (t.focus = Conversation || t.zoom)
            then Chat_search.clear t.chat_search
            else if t.zoom then (
              t.zoom <- false;
              t.focus <- Board;
              Chat_viewport.reset t.chat_viewport;
              t.scroll <- 0)
            else (
              t.query <- "";
              repair_selection t))
    | `ASCII '/' ->
        command (fun () ->
            act t
              (if t.focus = Conversation || t.zoom then Begin_chat_search
               else Begin_search))
    | `ASCII 'S' -> command (fun () -> act t Begin_chat_search)
    | `ASCII 'N' when Chat_search.query t.chat_search <> "" ->
        command (fun () -> act t Previous_chat_match)
    | `ASCII 'i' -> command (fun () -> act t Begin_compose)
    | `ASCII 'R' -> command (fun () -> act t Next_repository)
    | `ASCII 'b' -> command (fun () -> act t Session_board)
    | `ASCII 't' -> command (fun () -> act t Toggle_tools)
    | `ASCII 'm' -> command (fun () -> act t Begin_model)
    | `ASCII 'H' -> command (fun () -> act t Next_harness)
    | `ASCII 'v' -> command (fun () -> act t Open_review)
    | `ASCII 'W' -> command (fun () -> act t Begin_workspace)
    | `ASCII 'n'
      when Chat_search.query t.chat_search <> "" && (t.focus = Conversation || t.zoom) ->
        command (fun () -> act t Next_chat_match)
    | `ASCII 'n' -> command (fun () -> act t Begin_new)
    | `ASCII 's' | `Function 5 -> command (fun () -> act t Start)
    | `ASCII 'x' | `Function 6 -> command (fun () -> act t Stop)
    | `ASCII 'a' | `Function 7 -> command (fun () -> act t Accept)
    | `ASCII 'd' -> command (fun () -> act t Toggle_archive)
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
  else if t.live_confirmation <> None then (
    reset_keys t;
    match key with
    | `Escape | `ASCII 'n' -> act t Cancel_live
    | (`Enter | `ASCII 'y') when mods = [] -> act t Confirm_live
    | _ -> ())
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
    | `Page `Down -> t.menu_scroll <- min 10000 (t.menu_scroll + 8)
    | `Page `Up -> t.menu_scroll <- max 0 (t.menu_scroll - 8)
    | `ASCII 'm' when t.menu_tab = Settings_tab ->
        t.help <- false;
        act t Begin_model
    | `ASCII 'H' when t.menu_tab = Settings_tab -> act t Next_harness
    | _ -> ())
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
      | None -> t.status <- "Persistent storage is required for workspace creation."
      | Some worker -> (
          match Persistence.error worker with
          | Some error -> t.status <- "Storage error: " ^ error
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
          | Error error -> t.status <- error
          | Ok task ->
              t.tasks <- t.tasks @ [ task ];
              select t task.id;
              t.archive <- false;
              t.repository <- None;
              t.query <- "";
              t.workspace_form <- None;
              t.focus <- Conversation;
              t.status <-
                "Workspace task created / Queued. No agent starts. Saving conversation \
                 metadata."))

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
    t.status <-
      "Live UI enabled / no process started. s asks for confirmation on workspace tasks.";
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
