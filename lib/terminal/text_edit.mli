type t

val create : string -> t
(** Malformed UTF-8 is replaced with U+FFFD. Cursor positions are byte offsets at extended
    grapheme-cluster boundaries. LF and CRLF delimit logical lines. *)

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
