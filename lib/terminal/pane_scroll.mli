type pane = Chat | Activity
type t

val create : unit -> t
val clear : t -> unit
val position : t -> pane -> int
val remember : t -> pane -> int -> unit
