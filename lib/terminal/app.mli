val snapshot : size:string -> Controller.t -> unit

val interactive :
  ?allow_demo_history:bool ->
  ?projects:Project.t list ->
  ?fake_harness:bool ->
  ?live:Live_runner.config ->
  ?workspace_defaults:Workspace_defaults.t ->
  ?layout:Pane_layout.defaults ->
  events:string ->
  database:string ->
  unit ->
  (unit, string) result
