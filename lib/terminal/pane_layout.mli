type layout = Board | Detail | Stacked of int | Side_by_side of int
type result = Changed | At_limit | No_split
type defaults
type t

val automatic : defaults

val make_defaults :
  board_width:int option -> board_height:int option -> (defaults, string) Stdlib.result

val board_width : defaults -> int option
val board_height : defaults -> int option
val defaults : t -> defaults
val set_defaults : t -> defaults -> unit
val create : unit -> t
val hide : t -> unit
val reset : t -> unit
val resize : t -> detail:bool -> delta:int -> result

val choose :
  ?preferences:t -> width:int -> height:int -> detail_focused:bool -> unit -> layout
