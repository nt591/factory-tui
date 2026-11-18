type t = { awaiting : int; next : int }

val make : Model.task -> t
val title : width:int -> Model.task -> string
