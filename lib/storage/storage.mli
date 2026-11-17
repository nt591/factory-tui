type t

val open_store : string -> (t, string) result
val close : t -> unit
val load : t -> (Snapshot.t option, string) result
val save : t -> Snapshot.t -> events:Model.envelope list -> (unit, string) result

val read_events :
  t -> after:int64 -> limit:int -> ((int64 * Model.envelope) list, string) result
