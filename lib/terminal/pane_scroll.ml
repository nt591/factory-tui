type pane = Chat | Activity
type t = { mutable chat : int; mutable activity : int }

let create () = { chat = 0; activity = 0 }

let clear t =
  t.chat <- 0;
  t.activity <- 0

let position t = function Chat -> t.chat | Activity -> t.activity

let remember t pane value =
  match pane with Chat -> t.chat <- max 0 value | Activity -> t.activity <- max 0 value
