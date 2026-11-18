type t

val prepare : string -> t

val contains : t -> string -> bool
(** Match literal bytes with ASCII case folding. Empty queries match every string. *)
