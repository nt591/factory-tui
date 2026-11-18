val snapshot : size:string -> Controller.t -> unit

val interactive :
  ?fake_harness:bool ->
  ?live:Live_runner.config ->
  ?workspace_defaults:Workspace_defaults.t ->
  events:string ->
  database:string ->
  unit ->
  (unit, string) result
