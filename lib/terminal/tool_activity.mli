type t = { summary : string; details : string list }

val describe : id:string -> string -> t
val raw : string -> string list
