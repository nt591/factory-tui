val snapshot : size:string -> Controller.t -> unit

val interactive :
  ?fake_harness:bool -> events:string -> database:string -> unit -> (unit, string) result
