type t
type view = { offset : int; distance : int; following : bool }

val create : unit -> t
val reset : t -> unit
val distance : t -> int

val update :
  t ->
  task_id:string ->
  rows:(string * int) list ->
  height:int ->
  distance:int ->
  seek:string option ->
  view

val visible_rows : view -> height:int -> 'a list -> 'a list
