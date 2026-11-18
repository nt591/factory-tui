type state = Idle | Loading | Patch of string | Error of string
type t

val create : task_id:string -> Model.workspace_ref -> t
val task_id : t -> string
val state : t -> state
val start : t -> jj:string -> (unit, string) result
val poll : t -> unit
val close : t -> unit
