type t
type result = Edit | Cancel | Confirm

val create : Model.task -> t
val id : t -> string
val ready : t -> bool
val insert : t -> string -> unit
val key : t -> Notty.Unescape.key -> result
val rows : t -> string list
