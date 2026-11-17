open Model

type focus = Board | Conversation | Activity
type input = Normal | Search | Compose | New_task
type prefix = No_prefix | Go | Window
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
  mutable prefix : prefix;
  mutable count : int;
  mutable page_rows : int;
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
    last_click = None; prefix = No_prefix; count = 0; page_rows = 12; external_events }

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
let reset_keys t = t.prefix <- No_prefix; t.count <- 0
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

let act t action =
  reset_keys t;
  match action with
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

let ordered_tasks t =
  let tasks = visible t in
  if t.archive then tasks else
    List.concat_map (fun state -> List.filter (fun (task : task) -> task.state = state) tasks) columns

let navigation_tasks t =
  let tasks = ordered_tasks t in
  match selected t with
  | Some task when not t.archive -> List.filter (fun (x : task) -> x.state = task.state) tasks
  | _ -> tasks

let move_in t tasks delta =
  let rec index i = function
    | [] -> 0
    | (task : task) :: _ when task.id = t.selected -> i
    | _ :: rest -> index (i + 1) rest in
  if tasks <> [] then
    select t (List.nth tasks (max 0 (min (List.length tasks - 1) (index 0 tasks + delta)))).id

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
      else if t.archive then move_in t (ordered_tasks t) (if direction = `Left then -1 else 1)
      else match selected t with
        | None -> ()
        | Some task ->
          let states = if direction = `Left then List.rev columns else columns in
          let rec find = function
            | [] -> () | state :: rest when state = task.state -> next rest | _ :: rest -> find rest
          and next = function
            | [] -> () | state :: rest ->
                (match List.find_opt (fun (x : task) -> x.state = state) (ordered_tasks t) with
                 | Some x -> select t x.id | None -> next rest) in find states

let edge t last =
  if t.focus = Board && not t.zoom then (
    let tasks = navigation_tasks t in
    match (if last then List.rev tasks else tasks) with
    | task :: _ -> select t task.id | [] -> ())
  else if t.focus = Activity then t.scroll <- (if last then 1_000_000 else 0)
  else t.scroll <- (if last then 0 else 1_000_000)

let page t delta =
  if t.focus = Board && not t.zoom then move_in t (navigation_tasks t) delta
  else scroll t delta

let cycle_focus t backwards =
  t.focus <- (match t.focus, backwards with
    | Board, false | Activity, true -> Conversation
    | Conversation, false | Board, true -> Activity
    | Activity, false | Conversation, true -> Board);
  if t.zoom && t.focus = Board then t.focus <- (if backwards then Activity else Conversation);
  t.scroll <- 0

let window_focus t direction =
  let focus = match direction with
    | `Left -> if t.focus = Activity then Conversation else if t.zoom then Conversation else Board
    | `Right -> if t.focus = Board then Conversation else Activity
    | `Up -> if t.zoom then Conversation else Board
    | `Down -> if t.focus = Board then Conversation else Activity in
  t.focus <- focus; t.scroll <- 0

let repeat count fn = for _ = 1 to count do fn () done

let normal_key t (key, mods) =
  let count = max 1 t.count in
  let prefix = t.prefix in
  let command fn = reset_keys t; fn () in
  if List.mem `Ctrl mods then (
    command (fun () -> match key with
      | `ASCII 'w' -> if prefix = Window then cycle_focus t false else t.prefix <- Window
      | `ASCII 'h' when prefix = Window -> window_focus t `Left
      | `ASCII 'j' when prefix = Window -> window_focus t `Down
      | `ASCII 'k' when prefix = Window -> window_focus t `Up
      | `ASCII 'l' when prefix = Window -> window_focus t `Right
      | `ASCII 'u' -> page t (-count * max 1 (t.page_rows / 2))
      | `ASCII 'd' -> page t (count * max 1 (t.page_rows / 2))
      | `ASCII 'b' -> page t (-count * t.page_rows)
      | `ASCII 'f' -> page t (count * t.page_rows)
      | _ -> ()))
  else if key = `Tab then command (fun () -> cycle_focus t (List.mem `Shift mods))
  else if mods <> [] && mods <> [`Shift] then reset_keys t
  else if prefix = Window then command (fun () -> match key with
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
          t.count <- min 999 (t.count * 10 + Char.code digit - Char.code '0')
    | `ASCII 'g' -> t.prefix <- Go
    | `ASCII 'G' -> command (fun () -> edge t true)
    | `ASCII 'q' -> command (fun () -> act t Quit)
    | `ASCII '?' | `Function 1 -> command (fun () -> act t Help)
    | `ASCII 'e' | `Enter -> command (fun () -> act t Zoom)
    | `Escape -> command (fun () ->
        if t.zoom then (t.zoom <- false; t.focus <- Board; t.scroll <- 0)
        else (t.query <- ""; repair_selection t))
    | `ASCII '/' -> command (fun () -> act t Begin_search)
    | `ASCII 'i' -> command (fun () -> act t Begin_compose)
    | `ASCII 'n' -> command (fun () -> act t Begin_new)
    | `ASCII 's' | `Function 5 -> command (fun () -> act t Start)
    | `ASCII 'x' | `Function 6 -> command (fun () -> act t Stop)
    | `ASCII 'a' | `Function 7 -> command (fun () -> act t Accept)
    | `ASCII 'd' -> command (fun () -> act t Toggle_archive)
    | `ASCII 'f' -> command (fun () -> act t Toggle_pause)
    | `ASCII 'j' | `Arrow `Down -> command (fun () -> repeat count (fun () -> navigate t `Down))
    | `ASCII 'k' | `Arrow `Up -> command (fun () -> repeat count (fun () -> navigate t `Up))
    | `ASCII 'h' | `Arrow `Left -> command (fun () -> repeat count (fun () -> navigate t `Left))
    | `ASCII 'l' | `Arrow `Right -> command (fun () -> repeat count (fun () -> navigate t `Right))
    | `Page `Up -> command (fun () -> page t (-count * t.page_rows))
    | `Page `Down -> command (fun () -> page t (count * t.page_rows))
    | `Home -> command (fun () -> edge t false)
    | `End -> command (fun () -> edge t true)
    | _ -> reset_keys t)

let key t (key, mods) =
  (* Terminal input maps Ctrl letters to uppercase ASCII. *)
  let key = match key with
    | `ASCII char when List.mem `Ctrl mods -> `ASCII (Char.lowercase_ascii char)
    | key -> key in
  if key = `ASCII 'c' && List.mem `Ctrl mods then (reset_keys t; t.quit <- true)
  else if t.help then (reset_keys t; if key = `Escape || key = `ASCII '?' then t.help <- false)
  else if t.input <> Normal then (
    reset_keys t;
    match key with
    | `Escape -> t.input <- Normal
    | `Enter -> submit t
    | `Backspace -> set_input t (remove_last (input_value t))
    | `ASCII char when mods = [] || mods = [`Shift] -> set_input t (input_value t ^ clean ~newlines:false (String.make 1 char))
    | `Uchar uchar when mods = [] || mods = [`Shift] ->
        let b = Buffer.create 4 in append_utf8 b uchar;
        set_input t (input_value t ^ clean ~newlines:false (Buffer.contents b))
    | _ -> ())
  else normal_key t (key, mods)
