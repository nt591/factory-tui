type rect = { x : int; y : int; w : int; h : int }
type hit = { rect : rect; action : Controller.action }
type frame = { image : Notty.image; hits : hit list }

val wrap : int -> string -> string list
val wrap_title : int -> string -> string list
val hit_at : frame -> int -> int -> Controller.action option
val render : Controller.t -> width:int -> height:int -> frame
val mouse : Controller.t -> frame -> now:float -> Notty.Unescape.mouse -> unit
