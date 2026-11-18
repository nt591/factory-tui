val items :
  board:bool ->
  archive:bool ->
  task:Model.task option ->
  live:bool ->
  replay:bool ->
  fake:bool ->
  storage:bool ->
  expanded:bool ->
  (string * Controller.action) list
