type destination = Board | Archive

type item = {
  x : int;
  width : int;
  text : string;
  destination : destination;
  active : bool;
}

val make : width:int -> archive:bool -> count:int -> item list
val extent : item list -> int
