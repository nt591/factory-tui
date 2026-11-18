type t = {
  rows : string list;
  first : int;
  last : int;
  total : int;
  above : bool;
  below : bool;
}

val make : width:int -> capacity:int -> preview:string -> editor:Text_edit.t option -> t
val position : width:int -> t -> string
