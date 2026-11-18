type action = Run | Cancel
type hit = { x : int; y : int; width : int; action : action }
type view = { image : Notty.image; hits : hit list; readable : bool; content_rows : int }
type t

val create : unit -> t
val reset : t -> unit
val scroll : t -> int -> unit
val key : t -> Notty.Unescape.key -> unit
val can_confirm : t -> policy:Model.execution_policy -> Model.task option -> bool

val render :
  ?policy:Model.execution_policy ->
  ?viewport:t ->
  Model.task option ->
  width:int ->
  height:int ->
  view

val required_height :
  ?policy:Model.execution_policy -> Model.task option -> width:int -> int
