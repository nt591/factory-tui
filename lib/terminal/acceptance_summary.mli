type t = { queued : int; draft : bool }

val make : draft:string -> Model.task -> t
val status : t -> string
val title : width:int -> t -> string
