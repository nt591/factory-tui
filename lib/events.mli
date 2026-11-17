type source

val decode : string -> (Model.envelope, string) result
val encode : Model.envelope -> string
val open_source : string -> source
val poll : source -> (Model.envelope, string) result list
val close_source : source -> unit
