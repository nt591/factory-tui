open Model

type t = {
  tasks : task list;
  drafts : (string * string) list;
  selected : string;
  serial : int;
}

let string value = `String value
let integer value = `Int value
let boolean value = `Bool value
let list fn values = `List (List.map fn values)
let option fn = function None -> `Null | Some value -> fn value
let obj fields = `Assoc fields

let state = function
  | Queued -> "queued"
  | Working -> "working"
  | Needs_you -> "needs_you"
  | Ready -> "ready"
  | Done -> "done"

let status = function
  | Running -> "running"
  | Completed -> "completed"
  | Run_failed -> "failed"
  | Stopped -> "stopped"
  | Awaiting_input -> "input"

let harness = function Codex -> "codex" | Claude -> "claude"
let pair (key, value) = `List [ string key; string value ]

let run_record (run : run_record) =
  obj
    [
      ("id", string run.run_id);
      ("harness", string (harness run.harness));
      ("model", string run.model);
      ("started", `Float run.started_at);
      ("ended", option (fun n -> `Float n) run.ended_at);
      ("status", string (status run.status));
      ("simulated", boolean run.simulated);
    ]

let task (task : task) =
  obj
    [
      ("id", string task.id);
      ("title", string task.title);
      ("repository", string task.repository);
      ("state", string (state task.state));
      ("revision", integer task.revision);
      ("harness", string (harness task.harness));
      ("model", string task.model);
      ("thread", option string task.thread_id);
      ("runs", list run_record task.runs);
      ("tools", list pair task.tools);
      ( "messages",
        list
          (fun (m : message) ->
            obj
              [
                ("id", string m.id);
                ("author", string m.author);
                ("text", string m.text);
                ("queued", boolean m.queued);
              ])
          task.messages );
      ( "active",
        option
          (fun (run : run) ->
            obj
              [
                ("id", string run.id);
                ("submitted", list string run.submitted);
                ("completed", boolean run.completed);
                ("failed", boolean run.failed);
                ("input_requested", boolean run.input_requested);
              ])
          task.active );
    ]

let encode snapshot =
  Yojson.Basic.to_string
    (obj
       [
         ("version", integer 1);
         ("tasks", list task snapshot.tasks);
         ("drafts", list pair snapshot.drafts);
         ("selected", string snapshot.selected);
         ("serial", integer snapshot.serial);
       ])

exception Invalid

let invalid () = raise Invalid

let field name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with Some v -> v | None -> invalid ())
  | _ -> invalid ()

let text = function `String value -> value | _ -> invalid ()

let id json =
  let value = text json in
  if value = "" || String.length value > 1024 then invalid ();
  value

let int = function `Int n when n >= 0 -> n | _ -> invalid ()
let bool = function `Bool value -> value | _ -> invalid ()

let array fn = function
  | `List values when List.length values <= 100000 -> List.map fn values
  | _ -> invalid ()

let opt fn = function `Null -> None | json -> Some (fn json)

let time = function
  | `Float n when Float.is_finite n && n >= 0. -> n
  | `Int n when n >= 0 -> float_of_int n
  | _ -> invalid ()

let unique ids =
  if List.length (List.sort_uniq String.compare ids) <> List.length ids then invalid ()

let decode_pair = function
  | `List [ key; value ] -> (id key, text value)
  | _ -> invalid ()

let decode_state = function
  | "queued" -> Queued
  | "working" -> Working
  | "needs_you" -> Needs_you
  | "ready" -> Ready
  | "done" -> Done
  | _ -> invalid ()

let decode_status = function
  | "running" -> Running
  | "completed" -> Completed
  | "failed" -> Run_failed
  | "stopped" -> Stopped
  | "input" -> Awaiting_input
  | _ -> invalid ()

let decode_harness = function "codex" -> Codex | "claude" -> Claude | _ -> invalid ()

let decode_record json =
  let run =
    {
      run_id = id (field "id" json);
      harness = decode_harness (text (field "harness" json));
      model = id (field "model" json);
      started_at = time (field "started" json);
      ended_at = opt time (field "ended" json);
      status = decode_status (text (field "status" json));
      simulated =
        (match json with
        | `Assoc fields -> (
            match List.assoc_opt "simulated" fields with
            | None -> true
            | Some value -> bool value)
        | _ -> invalid ());
    }
  in
  if run.status = Running <> (run.ended_at = None) then invalid ();
  Option.iter (fun ended -> if ended < run.started_at then invalid ()) run.ended_at;
  run

let decode_task json =
  let task =
    {
      id = id (field "id" json);
      title = text (field "title" json);
      repository = text (field "repository" json);
      state = decode_state (text (field "state" json));
      revision = int (field "revision" json);
      harness = decode_harness (text (field "harness" json));
      model = id (field "model" json);
      thread_id = opt id (field "thread" json);
      runs = array decode_record (field "runs" json);
      tools = array decode_pair (field "tools" json);
      messages =
        array
          (fun json ->
            {
              id = id (field "id" json);
              author = text (field "author" json);
              text = text (field "text" json);
              queued = bool (field "queued" json);
            })
          (field "messages" json);
      active =
        opt
          (fun json ->
            {
              id = id (field "id" json);
              submitted = array id (field "submitted" json);
              completed = bool (field "completed" json);
              failed = bool (field "failed" json);
              input_requested = bool (field "input_requested" json);
            })
          (field "active" json);
    }
  in
  unique (List.map (fun (m : message) -> m.id) task.messages);
  unique (List.map (fun (r : run_record) -> r.run_id) task.runs);
  unique (List.map fst task.tools);
  let running = List.filter (fun (r : run_record) -> r.status = Running) task.runs in
  (match (task.active, task.state, running) with
  | None, (Queued | Needs_you | Ready | Done), [] -> ()
  | Some active, Working, [ record ] when active.id = record.run_id ->
      unique active.submitted;
      List.iter
        (fun id ->
          if not (List.exists (fun (m : message) -> m.id = id) task.messages) then
            invalid ())
        active.submitted
  | _ -> invalid ());
  task

let decode source =
  if String.length source > 16 * 1024 * 1024 then Error "Snapshot exceeds 16 MiB."
  else
    try
      let json = Yojson.Basic.from_string source in
      if int (field "version" json) <> 1 then invalid ();
      let snapshot =
        {
          tasks = array decode_task (field "tasks" json);
          drafts = array decode_pair (field "drafts" json);
          selected = text (field "selected" json);
          serial = int (field "serial" json);
        }
      in
      unique (List.map (fun (t : task) -> t.id) snapshot.tasks);
      unique (List.map fst snapshot.drafts);
      List.iter
        (fun (id, text) ->
          if
            String.length text > 65536
            || not (List.exists (fun (t : task) -> t.id = id) snapshot.tasks)
          then invalid ())
        snapshot.drafts;
      Ok snapshot
    with Invalid | Yojson.Json_error _ -> Error "Invalid or unsupported snapshot."

let recover snapshot =
  let now = Unix.gettimeofday () in
  let tasks =
    List.map
      (fun (task : task) ->
        if task.state <> Working then task
        else
          let task =
            {
              task with
              state = Needs_you;
              active = None;
              revision = task.revision + 1;
              runs =
                List.map
                  (fun (run : run_record) ->
                    if run.status <> Running then run
                    else
                      {
                        run with
                        status = Stopped;
                        ended_at = Some (max now run.started_at);
                      })
                  task.runs;
            }
          in
          Model.system task
            "Run interrupted by application restart. No agent was resumed.")
      snapshot.tasks
  in
  { snapshot with tasks }
