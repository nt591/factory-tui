type t
type file = { index : int; line : int; name : string }

val parse : string -> t
val line_count : t -> int
val lines : t -> start:int -> count:int -> string list
val file_count : t -> int
val fold_lines : t -> init:'a -> f:('a -> string -> 'a) -> 'a
val file_at : t -> line:int -> file option
val next_file : t -> line:int -> file option
val previous_file : t -> line:int -> file option
