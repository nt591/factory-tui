type item = Message of string | Tool of string | Lifecycle of string
type t = (string, (string * item, unit) Hashtbl.t) Hashtbl.t

let create () = Hashtbl.create 16
let reset t = Hashtbl.clear t
let clear t id = Hashtbl.remove t id
let count t id = Option.fold ~none:0 ~some:Hashtbl.length (Hashtbl.find_opt t id)

let record t (event : Model.envelope) =
  let item =
    match event.event with
    | Model.Message (id, _) -> Some (Message id)
    | Tool (id, _) -> Some (Tool id)
    | Input_requested _ -> Some (Lifecycle "input")
    | Failed _ -> Some (Lifecycle "failure")
    | Exited _ -> Some (Lifecycle "exit")
    | Interrupted -> Some (Lifecycle "stop")
    | Turn_started | Turn_completed | Thread_started _ -> None
  in
  Option.iter
    (fun item ->
      let items =
        match Hashtbl.find_opt t event.task_id with
        | Some items -> items
        | None ->
            let items = Hashtbl.create 8 in
            Hashtbl.add t event.task_id items;
            items
      in
      Hashtbl.replace items (event.run_id, item) ())
    item
