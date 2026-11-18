type t

val create : unit -> t
val query : t -> string
val set_query : t -> string -> unit
val clear : t -> unit
val sync : t -> Model.message list -> unit
val move : t -> backwards:bool -> unit
val matches : t -> string -> bool
val current : t -> string option
val position : t -> int * int
val seek : t -> string option
