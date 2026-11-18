type 'a t = { pinned : 'a list; repositories : 'a Board_window.t; cue : string }

val make :
  height:int -> selected:int -> scroll:int option -> pinned:'a list -> 'a list -> 'a t
