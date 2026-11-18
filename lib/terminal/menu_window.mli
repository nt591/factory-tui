type t = {
  rows : string list;
  scroll : int;
  capacity : int;
  first : int;
  last : int;
  total : int;
  above : bool;
  below : bool;
}

val make : height:int -> scroll:int -> string list -> t
val position : t -> string
