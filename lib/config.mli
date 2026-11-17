type t = { database : string option }

val parse : base:string -> home:string -> string -> (t, string) result
val load : home:string -> string -> (t, string) result
val default_path : home:string -> xdg:string option -> string

val resolve :
  home:string ->
  xdg:string option ->
  config:string option ->
  no_config:bool ->
  database:string option ->
  (string option, string) result
