type t

val create :
  jj:string ->
  source:string ->
  destination:string ->
  revision:string ->
  (t, string) result

val diff : jj:string -> t -> (string, string) result
val source : t -> string
val destination : t -> string
val base : t -> string
val name : t -> string
val reference : t -> Model.workspace_ref
val restore : Model.workspace_ref -> (t, string) result
