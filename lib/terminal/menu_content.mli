type mode = Simulation | Fake | Replay | Live of Model.execution_policy

val help : mode:mode -> string list

val settings :
  mode:mode -> database:string option -> task:Model.task option -> string list
