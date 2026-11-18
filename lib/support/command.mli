type output = { status : Unix.process_status; stdout : string; stderr_bytes : int }

val run :
  executable:string ->
  arguments:string list ->
  directory:string ->
  timeout:float ->
  max_output:int ->
  (output, string) result

val run_input :
  input:string ->
  executable:string ->
  arguments:string list ->
  directory:string ->
  timeout:float ->
  max_output:int ->
  (output, string) result
