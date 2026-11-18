type t = Board | Detail | Stacked of int | Side_by_side of int

val choose : width:int -> height:int -> detail_focused:bool -> t
