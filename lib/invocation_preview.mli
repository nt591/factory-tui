val build :
  executable:string ->
  directory:string ->
  model:string ->
  thread_id:string option ->
  gateway_file:string option ->
  (Yojson.Basic.t, string) result
