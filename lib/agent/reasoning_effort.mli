type t = Low | Medium | High

val parse : string -> (t, string) result
val label : t -> string
