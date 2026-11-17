type t

val create : unit -> t
val poll : t -> Controller.t -> storage:Persistence.t option -> unit
val close : t -> Controller.t -> unit
