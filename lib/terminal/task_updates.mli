type t

val create : unit -> t
val reset : t -> unit
val clear : t -> string -> unit
val count : t -> string -> int

val record : t -> Model.envelope -> unit
(** Call only for an event accepted by the task reducer. Stream replacements share a key.
*)
