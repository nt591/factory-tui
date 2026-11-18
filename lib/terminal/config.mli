type t = {
  database : string option;
  workspace : Workspace_defaults.t;
  layout : Pane_layout.defaults;
}

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

val resolve_settings :
  home:string ->
  xdg:string option ->
  config:string option ->
  no_config:bool ->
  database:string option ->
  (t, string) result
