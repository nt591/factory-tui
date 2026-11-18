type t

val create : unit -> t
val position : t -> Model.state -> int option
val offset : t -> Model.state -> int
val set : t -> Model.state -> int -> unit
val follow : t -> Model.state -> unit
val clear : t -> unit
