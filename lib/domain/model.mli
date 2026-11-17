type state = Queued | Working | Needs_you | Ready | Done
type message = { id : string; author : string; text : string; queued : bool }
type harness = Codex | Claude
type run_status = Running | Completed | Run_failed | Stopped | Awaiting_input

type run_record = {
  run_id : string;
  harness : harness;
  model : string;
  started_at : float;
  ended_at : float option;
  status : run_status;
  simulated : bool;
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
  | Turn_started
  | Thread_started of string
  | Message of string * string
  | Tool of string * string
  | Turn_completed
  | Failed of string
  | Input_requested of string
  | Exited of int
  | Interrupted

type envelope = { task_id : string; run_id : string; event : event }

val columns : state list
val label : state -> string
val harness_label : harness -> string
val make : id:string -> title:string -> repository:string -> task
val system : task -> string -> task
val set_model : task -> string -> (task, string) result
val set_harness : task -> harness -> (task, string) result
val start : ?simulated:bool -> task -> string -> (task, string) result
val send : task -> id:string -> string -> (task, string) result
val accept : task -> (task, string) result
val apply : task -> envelope -> task option
val reduce : task list -> envelope -> task list
