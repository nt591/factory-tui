type context = {
  tasks : unit -> Model.task list;
  snapshot : unit -> Snapshot.t;
  pending_events : unit -> Model.envelope list;
  acknowledge_events : unit -> unit;
  receive : Model.envelope -> unit;
  report_error : string -> unit;
  enabled : unit -> bool;
  quitting : unit -> bool;
}

type t

val create : unit -> t
val poll : t -> context -> storage:Persistence.t option -> unit
val close : t -> context -> unit
