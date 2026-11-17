type t

val start :
  ?capacity:int ->
  ?checkpoint:(unit -> (unit, string) result) ->
  Process.config ->
  prompt:string ->
  t

val cancel : t -> unit
val drain : t -> Harness.decoded list
val outcome : t -> (Process.outcome, string) result option
val close : t -> unit
