type choice = Fetch | Close | Model of string
type hit = { x : int; y : int; width : int; choice : choice }
type t = { rows : string list; footer : string; hits : hit list }

val make : Model_picker.t -> width:int -> height:int -> t
