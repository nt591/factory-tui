type state = Idle | Loading | Models of string list | Error of string
type t

val create : unit -> t
val state : t -> state
val reset : t -> unit
val query : t -> string
val visible : t -> string list
val selected : t -> string option
val index : t -> int
val capacity : t -> int -> unit
val move : t -> int -> unit
val key : t -> Notty.Unescape.key -> unit
val insert : t -> string -> unit
val refresh : t -> (unit -> (string list, string) result) -> unit
val poll : t -> unit
val close : t -> unit
