type t = { text : string; latest : (int * int) option }

val make : width:int -> height:int -> total:int -> Chat_viewport.view -> t
