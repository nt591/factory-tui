type t
type document

val create : unit -> t
val clear : t -> unit
val update : t -> task_id:string -> (string * string) list -> document
val describe : document -> id:string -> payload:string -> Tool_activity.t
val raw : document -> id:string -> payload:string -> string list
