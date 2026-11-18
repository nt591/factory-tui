type t

val create : Diff_document.t -> t
val widest : t -> int
val lines : t -> start:int -> count:int -> string list
