type state = Queued | Working | Needs_you | Ready | Done
let columns = [ Queued; Working; Needs_you; Ready ]
let label = function
  | Queued -> "Queued" | Working -> "Working" | Needs_you -> "Needs you"
  | Ready -> "Ready" | Done -> "Done"

type message = { id : string; author : string; text : string; queued : bool }
type harness = Codex | Claude
let harness_label = function Codex -> "Codex" | Claude -> "Claude"

type run_status = Running | Completed | Run_failed | Stopped | Awaiting_input
type run_record = {
  run_id : string;
  harness : harness;
  model : string;
  started_at : float;
  ended_at : float option;
  status : run_status;
}

type run = {
  id : string;
  submitted : string list;
  completed : bool;
  failed : bool;
  input_requested : bool;
}
type task = {
  id : string;
  title : string;
  repository : string;
  state : state;
  messages : message list;
  tools : (string * string) list;
  active : run option;
  thread_id : string option;
  revision : int;
  harness : harness;
  model : string;
  runs : run_record list;
}
type event =
  | Turn_started | Thread_started of string | Message of string * string
  | Tool of string * string | Turn_completed | Failed of string
  | Input_requested of string | Exited of int | Interrupted

type envelope = { task_id : string; run_id : string; event : event }

let make ~id ~title ~repository =
  { id; title; repository; state = Queued;
    messages = [{ id = id ^ "/prompt"; author = "You"; text = title; queued = true }];
    tools = []; active = None; thread_id = None; revision = 0;
    harness = Codex; model = "coding-large"; runs = [] }

let system task text =
  { task with messages = task.messages @
      [{ id = Printf.sprintf "%s/system/%d" task.id task.revision;
         author = "Factory"; text; queued = false }] }

let set_model task value =
  let value = String.trim value in
  if value = "" || value.[0] = '-' || String.length value > 256 ||
     String.exists (fun char -> Char.code char < 32 || Char.code char = 127) value then
    Error "Enter a model ID without controls, up to 256 bytes."
  else if task.state = Done then Error "Accepted tasks are read-only."
  else Ok { task with model = value; revision = task.revision + 1 }

let set_harness task harness =
  if task.state = Done then Error "Accepted tasks are read-only."
  else Ok { task with harness; revision = task.revision + 1 }

let start task run_id =
  if List.exists (fun (run : run_record) -> run.run_id = run_id) task.runs then Error "Run ID is already recorded."
  else if task.state = Working || task.state = Done then Error "Task cannot start in this state."
  else if not (List.exists (fun (m : message) -> m.queued) task.messages) then
    Error "Post an instruction before starting a run."
  else
    let submitted = List.filter_map (fun (m : message) -> if m.queued then Some m.id else None) task.messages in
    Ok { task with state = Working; revision = task.revision + 1;
         runs = task.runs @ [{ run_id; harness = task.harness; model = task.model;
                              started_at = Unix.gettimeofday (); ended_at = None; status = Running }];
         active = Some { id = run_id; submitted; completed = false; failed = false;
                         input_requested = false } }

let send task ~id text =
  if String.trim text = "" then Error "Message is empty."
  else if task.state = Done then Error "Accepted tasks are read-only."
  else if String.length text > 65536 then Error "Message exceeds 64 KiB."
  else Ok { task with messages = task.messages @
              [{ id; author = "You"; text; queued = true }]; revision = task.revision + 1 }

let accept task =
  if task.state <> Ready then Error "Only Ready tasks can be accepted."
  else Ok { task with state = Done; revision = task.revision + 1 }

let apply task (envelope : envelope) =
  match task.active with
  | Some run when task.id = envelope.task_id && run.id = envelope.run_id && task.state = Working ->
      let task = { task with revision = task.revision + 1 } in
      let update run = { task with active = Some run } in
      let finish state status =
        { task with state; active = None; runs = List.map (fun (record : run_record) ->
            if record.run_id = run.id then
              { record with status; ended_at = Some (Unix.gettimeofday ()) }
            else record) task.runs } in
      Some (match envelope.event with
        | Turn_started -> { task with messages = List.map (fun (m : message) ->
            if List.mem m.id run.submitted then { m with queued = false } else m) task.messages }
        | Thread_started id -> { task with thread_id = Some id }
        | Message (id, text) ->
            let id = run.id ^ "/" ^ id in
            let author = match List.find_opt (fun (record : run_record) -> record.run_id = run.id) task.runs with
              | Some record -> harness_label record.harness ^ " (simulated)"
              | None -> "Agent (simulated)" in
            let message = { id; author; text; queued = false } in
            let messages = if List.exists (fun (m : message) -> m.id = id) task.messages
              then List.map (fun (m : message) -> if m.id = id then message else m) task.messages
              else task.messages @ [message] in
            { task with messages }
        | Tool (id, text) ->
            let id = run.id ^ "/" ^ id in
            { task with tools = List.remove_assoc id task.tools @ [id, text] }
        | Turn_completed -> update { run with completed = true }
        | Failed text -> system (update { run with failed = true }) ("Run failed: " ^ text)
        | Input_requested text ->
            system (update { run with input_requested = true }) ("Needs your input: " ^ text)
        | Interrupted -> system (finish Needs_you Stopped) "Run interrupted. Replies remain queued."
        | Exited code ->
            if code = 0 && run.completed && not run.failed && not run.input_requested then finish Ready Completed
            else system (finish Needs_you (if run.input_requested && not run.failed && code = 0 then Awaiting_input else Run_failed))
                (if run.input_requested then "Run paused for your reply."
                 else if run.failed then "Run failed. Inspect the activity before retrying."
                 else Printf.sprintf "Run exited (%d) without validated completion." code))
  | _ -> None

let reduce tasks envelope =
  List.map (fun task -> match apply task envelope with Some updated -> updated | None -> task) tasks
