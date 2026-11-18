type action = Submit | Close | Newline
type item = { label : string; action : action }

val items : Controller.input -> item list
val key : input:Controller.input -> action -> Notty.Unescape.key option
