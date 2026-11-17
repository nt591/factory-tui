type summary = {
  task_id : string;
  thread_id : string option;
  state : Model.state;
  succeeded : bool;
}

val run :
  executable:string ->
  directory:string ->
  model:string ->
  thread_id:string option ->
  gateway_file:string option ->
  database:string ->
  prompt:string ->
  cancelled:(unit -> bool) ->
  (summary, string) result
