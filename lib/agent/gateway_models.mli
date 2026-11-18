val decode : string -> (string list, string) result
val url : Gateway.t -> string

val fetch :
  curl:string ->
  lookup:(string -> string option) ->
  Gateway.t ->
  (string list, string) result
