type t

val create : Model.task -> jj:string -> (t, string) result
val task_id : t -> string
val title : t -> string
val executable : t -> string
val executable_cursor_parts : t -> string * string
val editing : t -> bool
val state : t -> Changes.state
val document : t -> Diff_document.t option
val display : t -> Diff_display.t option
val set_page_rows : t -> int -> unit
val jump_file : t -> [ `Next | `Previous ] -> unit
val scroll : t -> int
val set_scroll : t -> int -> unit
val horizontal : t -> int
val set_horizontal : t -> int -> unit
val refresh : t -> unit
val status : t -> string option
val edit_executable : t -> unit
val key : t -> Notty.Unescape.key -> unit
val paste_key : t -> Notty.Unescape.key -> unit
val poll : t -> unit
val close : t -> unit
