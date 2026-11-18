type action = Toggle_archive | Search
type hit = { x : int; width : int; action : action }
type t = { text : string; hits : hit list }

val make :
  width:int -> archive:bool -> repository:string option -> count:int -> query:string -> t
