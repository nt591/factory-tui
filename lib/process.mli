type config = {
  executable : string;
  arguments : string list;
  directory : string;
  timeout : float;
  max_line : int;
  max_stream : int;
  max_events : int;
}

type outcome = {
  status : Unix.process_status;
  succeeded : bool;
  interrupted : bool;
  events : int;
  stdout_bytes : int;
  stderr_bytes : int;
}

val defaults : executable:string -> arguments:string list -> directory:string -> config

val run :
  config ->
  prompt:string ->
  cancelled:(unit -> bool) ->
  on_event:(Harness.decoded -> unit) ->
  (outcome, string) result
