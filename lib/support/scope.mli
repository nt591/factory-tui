val ( let@ ) : (('a -> 'b) -> 'b) -> ('a -> 'b) -> 'b

val on_exit : (unit -> unit) -> (unit -> 'a) -> 'a
(** Cleanup runs after the body returns or raises. Nested scopes clean up inside out.
    Cleanup exceptions retain [Fun.protect] semantics. *)
