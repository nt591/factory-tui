type action = Run | Cancel
type hit = { x : int; y : int; width : int; action : action }
type view = { image : Notty.image; hits : hit list; readable : bool }

val render : Model.task option -> width:int -> height:int -> view
