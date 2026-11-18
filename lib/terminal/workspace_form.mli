type field = Jj | Source | Parent | Revision | Model | Task
type t

val create :
  ?jj:string ->
  source:string ->
  parent:string ->
  revision:string ->
  model:string ->
  unit ->
  t

val fields : field list
val label : field -> string
val current : t -> field
val status : t -> string
val report : t -> string -> unit
val value : t -> field -> string
val cursor_parts : t -> field -> string * string
val focus : t -> field -> unit
val key : t -> Notty.Unescape.key -> unit
val paste_key : t -> Notty.Unescape.key -> unit
val validate : t -> (unit, string) result
val validate_submission : t -> (unit, string) result
val set_model : t -> string -> (unit, string) result
val set_project : t -> Project.t -> unit
val greenfield : t -> bool
val toggle_greenfield : t -> unit
val folder_root : t -> bool
val toggle_folder_root : t -> unit
