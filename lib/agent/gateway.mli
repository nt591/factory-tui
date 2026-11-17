type t

val make : base_url:string -> key_environment:string -> (t, string) result
val parse : string -> (t, string) result
val load : string -> (t, string) result
val base_url : t -> string
val key_environment : t -> string
