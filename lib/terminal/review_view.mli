type action = Refresh | Edit_executable | Close
type hit = { x : int; y : int; width : int; action : action }
type t = { image : Notty.image; hits : hit list }

val render : Review.t -> width:int -> height:int -> t
