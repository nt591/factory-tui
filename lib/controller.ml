open Model

type focus = Board | Conversation | Activity
type input = Normal | Search | Compose | New_task
type action =
  | Select of string | Zoom | Focus of focus | Start | Stop | Accept
  | Toggle_archive | Toggle_pause | Help | Quit | Begin_search | Begin_compose | Begin_new

type t = {
  mutable tasks : task list;
  mutable selected : string;
  mutable focus : focus;
  mutable zoom : bool;
  mutable archive : bool;
  mutable paused : bool;
  mutable help : bool;
  mutable input : input;
  mutable query : string;
  mutable new_title : string;
  mutable drafts : (string * string) list;
  mutable scroll : int;
  mutable board_scroll : int;
  mutable status : string;
  mutable quit : bool;
  mutable serial : int;
  mutable schedules : (float * envelope) list;
  mutable last_click : (string * float) option;
  external_events : bool;
}

let create ?(external_events = false) () =
  { tasks = Demo.seed (); selected = "T-102"; focus = Board; zoom = false;
    archive = false; paused = false; help = false; input = Normal; query = "";
    new_title = ""; drafts = []; scroll = 0; board_scroll = 0;
    status = "Simulation only. No agent, credentials, or workspace access.";
    quit = false; serial = 200;
    schedules = if external_events then [] else
      List.map (fun (delay, e) -> Unix.gettimeofday () +. delay, e) (Demo.schedule "T-102" "demo-102");
    last_click = None; external_events }

let contains text query =
  let text = String.lowercase_ascii text and query = String.lowercase_ascii query in
  let rec loop i = i + String.length query <= String.length text &&
    (String.sub text i (String.length query) = query || loop (i + 1)) in
  loop 0

let visible t = List.filter (fun (task : task) ->
  (if t.archive then task.state = Done else task.state <> Done) &&
  contains (task.id ^ " " ^ task.title ^ " " ^ task.repository) t.query) t.tasks

let selected t = List.find_opt (fun (task : task) -> task.id = t.selected) t.tasks
let draft t = Option.value ~default:"" (List.assoc_opt t.selected t.drafts)
let set_draft t text = t.drafts <- (t.selected, text) :: List.remove_assoc t.selected t.drafts
let next_id t prefix = t.serial <- t.serial + 1; Printf.sprintf "%s-%d" prefix t.serial
let replace t (task : task) = t.tasks <- List.map (fun (old : task) -> if old.id = task.id then task else old) t.tasks
let result t = function Ok task -> replace t task | Error error -> t.status <- error
let select t id = t.selected <- id; t.scroll <- 0; t.board_scroll <- 0
let repair_selection t =
  if not (List.exists (fun (task : task) -> task.id = t.selected) (visible t)) then
    match visible t with task :: _ -> select t task.id | [] -> t.selected <- ""

let receive t event = t.tasks <- reduce t.tasks event
let tick t now =
  if not t.paused then (
    let due, later = List.partition (fun (time, _) -> time <= now) t.schedules in
    t.schedules <- later;
    List.iter (fun (_, event) -> receive t event) due)

let act t = function
  | Select id -> select t id; t.focus <- Board
  | Focus focus -> t.focus <- focus
  | Zoom -> t.zoom <- not t.zoom; t.focus <- Conversation; t.scroll <- 0
  | Quit -> t.quit <- true
  | Help -> t.help <- not t.help
  | Begin_search -> t.input <- Search
  | Begin_compose -> if selected t <> None then (t.input <- Compose; t.focus <- Conversation)
  | Begin_new -> t.input <- New_task; t.new_title <- ""
  | Toggle_pause ->
      if t.external_events then t.status <- "Replay input stays live. Pause is available for the demo only."
      else (t.paused <- not t.paused;
        if not t.paused then t.schedules <- List.mapi (fun i (_, e) ->
          Unix.gettimeofday () +. float_of_int i *. 0.5, e) t.schedules)
  | Toggle_archive -> t.archive <- not t.archive; t.board_scroll <- 0; repair_selection t
  | Start ->
      if t.external_events then t.status <- "Replay mode cannot start runs. Use a fixture run ID."
      else (match selected t with
        | None -> ()
        | Some task ->
          let run_id = next_id t "demo-run" in
          (match start task run_id with
           | Error error -> t.status <- error
           | Ok task -> replace t task;
             t.schedules <- t.schedules @ List.map (fun (delay, e) ->
               Unix.gettimeofday () +. delay, e) (Demo.schedule task.id run_id);
             t.status <- "Simulated run started. Cards follow lifecycle events."))
  | Stop -> (match selected t with
      | Some { active = Some run; id; _ } ->
          receive t { task_id = id; run_id = run.id; event = Interrupted };
          t.status <- "Simulated run interrupted. Stale updates are ignored."
      | _ -> t.status <- "There is no active run to stop.")
  | Accept -> (match selected t with
      | Some task -> result t (accept task); repair_selection t
      | None -> ())

let append_utf8 buffer uchar = Uutf.Buffer.add_utf_8 buffer uchar
let clean ?(newlines = true) text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8 (fun () _ -> function
    | `Malformed _ -> append_utf8 buffer Uutf.u_rep
    | `Uchar u -> let n = Uchar.to_int u in
        if n = 10 && newlines then Buffer.add_char buffer '\n'
        else if n < 32 || (n >= 127 && n <= 159) then Buffer.add_char buffer ' '
        else append_utf8 buffer u) () text;
  Buffer.contents buffer

let remove_last text =
  let last = ref 0 in
  Uutf.String.fold_utf_8 (fun () i _ -> last := i) () text;
  String.sub text 0 !last

let input_value t = match t.input with
  | Search -> t.query | Compose -> draft t | New_task -> t.new_title | Normal -> ""
let set_input t text =
  if String.length text <= 65536 then match t.input with
    | Search -> t.query <- text; t.board_scroll <- 0; repair_selection t
    | Compose -> set_draft t text
    | New_task -> t.new_title <- text
    | Normal -> ()

let submit t = match t.input with
  | Normal | Search -> t.input <- Normal
  | Compose -> (match selected t with
      | None -> t.input <- Normal
      | Some task -> match send task ~id:(next_id t "message") (draft t) with
        | Error error -> t.status <- error
        | Ok task -> replace t task; set_draft t ""; t.input <- Normal;
          t.status <- "Reply queued for the next run. No live agent receives it.")
  | New_task ->
      let title = String.trim t.new_title in
      if title <> "" then (
        let id = next_id t "T" in
        t.tasks <- t.tasks @ [make ~id ~title ~repository:"factory-tui"];
        t.archive <- false; t.query <- ""; select t id; t.input <- Normal;
        t.status <- "Task created in memory. Start runs a simulated fixture.")

let navigate t direction =
  let tasks = visible t in
  let tasks = if t.archive then tasks else
    List.concat_map (fun state -> List.filter (fun (task : task) -> task.state = state) tasks) columns in
  let move_in list delta =
    let rec index i = function
      | [] -> 0 | (task : task) :: _ when task.id = t.selected -> i | _ :: rest -> index (i + 1) rest in
    if list <> [] then select t (List.nth list (max 0 (min (List.length list - 1) (index 0 list + delta)))).id in
  match direction with
  | `Up | `Down ->
      let delta = if direction = `Up then -1 else 1 in
      if t.focus <> Board || t.zoom then
        t.scroll <- max 0 (t.scroll + (if t.focus = Activity then delta else -delta) * 2)
      else (let list = match selected t with
        | Some task when not t.archive -> List.filter (fun (x : task) -> x.state = task.state) tasks
        | _ -> tasks in move_in list delta)
  | `Left | `Right ->
      if t.archive then move_in tasks (if direction = `Left then -1 else 1)
      else match selected t with
        | None -> ()
        | Some task ->
          let states = if direction = `Left then List.rev columns else columns in
          let rec find = function
            | [] -> () | state :: rest when state = task.state -> next rest | _ :: rest -> find rest
          and next = function
            | [] -> () | state :: rest ->
                (match List.find_opt (fun (x : task) -> x.state = state) tasks with
                 | Some x -> select t x.id | None -> next rest) in find states

let key t (key, mods) =
  if key = `ASCII 'c' && List.mem `Ctrl mods then t.quit <- true
  else if t.help then (if key = `Escape || key = `ASCII '?' then t.help <- false)
  else if t.input <> Normal then (
    match key with
    | `Escape -> t.input <- Normal
    | `Enter -> submit t
    | `Backspace -> set_input t (remove_last (input_value t))
    | `ASCII char when mods = [] || mods = [`Shift] -> set_input t (input_value t ^ clean ~newlines:false (String.make 1 char))
    | `Uchar uchar when mods = [] || mods = [`Shift] ->
        let b = Buffer.create 4 in append_utf8 b uchar;
        set_input t (input_value t ^ clean ~newlines:false (Buffer.contents b))
    | _ -> ())
  else match key with
    | `ASCII 'q' -> act t Quit
    | `ASCII '?' | `Function 1 -> act t Help
    | `ASCII 'e' | `Enter -> act t Zoom
    | `Escape -> if t.zoom then t.zoom <- false else (t.query <- ""; repair_selection t)
    | `ASCII '/' -> act t Begin_search
    | `ASCII 'i' -> act t Begin_compose
    | `ASCII 'n' -> act t Begin_new
    | `ASCII 's' | `Function 5 -> act t Start
    | `ASCII 'x' | `Function 6 -> act t Stop
    | `ASCII 'a' | `Function 7 -> act t Accept
    | `ASCII 'd' -> act t Toggle_archive
    | `ASCII 'f' -> act t Toggle_pause
    | `Tab -> t.focus <- (match t.focus with Board -> Conversation | Conversation -> Activity | Activity -> Board); t.scroll <- 0
    | `ASCII 'j' | `Arrow `Down -> navigate t `Down
    | `ASCII 'k' | `Arrow `Up -> navigate t `Up
    | `ASCII 'h' | `Arrow `Left -> navigate t `Left
    | `ASCII 'l' | `Arrow `Right -> navigate t `Right
    | `Page `Up -> if t.focus = Board && not t.zoom then t.board_scroll <- max 0 (t.board_scroll - 1) else t.scroll <- max 0 (t.scroll + (if t.focus = Activity then -8 else 8))
    | `Page `Down -> if t.focus = Board && not t.zoom then t.board_scroll <- t.board_scroll + 1 else t.scroll <- max 0 (t.scroll + (if t.focus = Activity then 8 else -8))
    | `Home -> t.scroll <- (if t.focus = Conversation || t.zoom then 65536 else 0); t.board_scroll <- 0
    | `End -> t.scroll <- 0
    | _ -> ()
