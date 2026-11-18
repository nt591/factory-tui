type t

val create : form:Workspace_form.t -> Project.t list -> t
val form : t -> Workspace_form.t
val query : t -> string
val visible : t -> Project.t list
val selected : t -> Project.t option
val index : t -> int
val capacity : t -> int -> unit
val move : t -> int -> unit
val insert : t -> string -> unit
val key : t -> Notty.Unescape.key -> unit
