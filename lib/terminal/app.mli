val snapshot : size:string -> Controller.t -> unit

val interactive :
  ?fake_harness:bool ->
  ?live:Live_runner.config ->
  events:string ->
  database:string ->
  unit ->
  (unit, string) result
