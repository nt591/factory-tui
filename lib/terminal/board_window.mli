type 'a t = {
  items : 'a list;
  offset : int;
  first : int;
  last : int;
  total : int;
  above : bool;
  below : bool;
}

val make : capacity:int -> selected:int -> scroll:int -> 'a list -> 'a t
val cue : 'a t -> string
