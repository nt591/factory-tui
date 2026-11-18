type layout = Board | Detail | Stacked of int | Side_by_side of int
type result = Changed | At_limit | No_split
type t

val create : unit -> t
val hide : t -> unit
val reset : t -> unit
val resize : t -> detail:bool -> delta:int -> result

val choose :
  ?preferences:t -> width:int -> height:int -> detail_focused:bool -> unit -> layout
