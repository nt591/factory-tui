type command =
  | Board
  | Archive
  | New_task
  | Reply
  | Model
  | Models
  | Stop
  | Accept
  | Restore
  | Clear_reply
  | Delete
  | Review
  | Help

type entry = {
  command : command;
  title : string;
  shortcut : string;
  disabled : string option;
}

type t
type result = Edit | Cancel | Execute of command

val catalogue :
  board:bool ->
  task:Model.task option ->
  live:bool ->
  replay:bool ->
  storage:bool ->
  busy:bool ->
  entry list

val create : entry list -> t
val update : t -> entry list -> unit
val editor : t -> Text_edit.t
val query : t -> string
val visible : t -> entry list
val selected : t -> entry option
val index : t -> int
val move : t -> int -> unit
val insert : t -> string -> unit
val choose : t -> command -> result
val key : t -> Notty.Unescape.key -> result
