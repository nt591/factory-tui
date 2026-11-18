type action = Refresh | Edit_executable | Close | Next_file | Previous_file
type hit = { x : int; y : int; width : int; action : action }
type scroll_region = { x : int; y : int; width : int; height : int }
type t = { image : Notty.image; hits : hit list; scroll_region : scroll_region option }

val render : Review.t -> width:int -> height:int -> t
