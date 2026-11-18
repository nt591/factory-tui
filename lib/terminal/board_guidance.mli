type action = Create_workspace | Create_demo | Clear_filters | Open_board
type t = { title : string; lines : string list; button : string; action : action }

val empty : live:bool -> has_tasks:bool -> archived:bool -> filtered:bool -> t
