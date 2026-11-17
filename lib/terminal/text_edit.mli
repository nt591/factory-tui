type t

val create : string -> t
val text : t -> string
val cursor : t -> int
val insert : t -> string -> t
val left : t -> t
val right : t -> t
val home : t -> t
val ending : t -> t
val up : t -> t
val down : t -> t
val backspace : t -> t
val delete : t -> t
