val invocation :
  executable:string ->
  directory:string ->
  model:string ->
  thread_id:string option ->
  (Process.config, string) result
