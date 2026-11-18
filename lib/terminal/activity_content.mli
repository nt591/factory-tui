val lines :
  ?tools:Tool_cache.document ->
  now:float ->
  expanded:bool ->
  raw:bool ->
  waiting:bool ->
  Model.task option ->
  string list
