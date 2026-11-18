type t
type document
type tone = Author of bool | Body | Spacer

type row = { id : string; index : int; text : string; tone : tone }
(** Header indices are non-positive and end at zero. Body indices start at one. *)

val create : unit -> t
val clear : t -> unit
val update : t -> task_id:string -> width:int -> Model.message list -> document
val rows : document -> row list
val anchors : document -> (string * int) list
