val wrap : int -> string -> string list
(** Input must be sanitized UTF-8. LF line separators are accepted. *)

val wrap_positions : int -> string -> (int * string) list
(** Each row includes its starting byte offset in sanitized UTF-8 input. LF is accepted.
*)

val wrap_words : int -> string -> string list
val ellipsize : ?more:bool -> int -> string -> string
val limit_rows : width:int -> height:int -> string list -> string list
val cursor_window : int -> before:string -> after:string -> string
