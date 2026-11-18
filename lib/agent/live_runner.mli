type config

val configure : executable:string -> gateway_file:string option -> (config, string) result
val with_reasoning : config -> Reasoning_effort.t -> config
val reasoning : config -> Reasoning_effort.t option
val with_policy : config -> Model.execution_policy -> config
val gateway : config -> Gateway.t option
val policy : config -> Model.execution_policy
val policy_label : config -> string
val prepare : config -> Model.task -> (Process.config * string, string) result

type context = {
  tasks : unit -> Model.task list;
  snapshot : unit -> Snapshot.t;
  pending_events : unit -> Model.envelope list;
  acknowledge_events : unit -> unit;
  receive : Model.envelope -> unit;
  report_error : string -> unit;
  quitting : unit -> bool;
}

type t

val owned_tasks : t -> string list
val create : config -> t
val waiting_tasks : t -> string list
val poll : t -> context -> storage:Persistence.t -> unit
val close : t -> context -> unit
