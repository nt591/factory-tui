type action = Toggle_archive | Search | Reveal_selected
type hit = { x : int; width : int; action : action }
type t = { text : string; hits : hit list }

val make :
  width:int ->
  archive:bool ->
  repository:string option ->
  count:int ->
  query:string ->
  hidden:bool ->
  t
