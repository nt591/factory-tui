type t = { mutable offsets : (Model.state * int) list }

let create () = { offsets = [] }
let position t state = List.assoc_opt state t.offsets
let offset t state = Option.value ~default:0 (position t state)

let set t state value =
  t.offsets <- (state, max 0 value) :: List.remove_assoc state t.offsets

let follow t state = t.offsets <- List.remove_assoc state t.offsets
let clear t = t.offsets <- []
