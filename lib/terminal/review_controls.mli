type action = Refresh | Edit_executable | Close | Next_file | Previous_file
type hit = { x : int; width : int; action : action }
type t = { text : string; hits : hit list }

val make : width:int -> editing:bool -> files:bool -> t
