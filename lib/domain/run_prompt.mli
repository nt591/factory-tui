val queued : Model.task -> Model.message list
val submitted : Model.task -> string list -> Model.message list
val text : Model.message list -> string
val byte_length : Model.message list -> int
