val wrap : int -> string -> string list
(** Input must be sanitized UTF-8. Only [wrap] accepts newline characters. *)

val wrap_words : int -> string -> string list
