type t

val start : string -> (t * Snapshot.t option, string) result
val submit : t -> Snapshot.t -> events:Model.envelope list -> (unit, string) result
val flush : t -> (unit, string) result
val error : t -> string option
val close : t -> (unit, string) result
