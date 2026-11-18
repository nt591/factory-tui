type item = {
  payload : string;
  description : Tool_activity.t Lazy.t;
  raw : string list Lazy.t;
}

type document = (string, item) Hashtbl.t
type cached = { task_id : string; tools : (string * string) list; document : document }
type t = { mutable cached : cached option }

let create () = { cached = None }
let clear t = t.cached <- None

let item id payload =
  {
    payload;
    description = lazy (Tool_activity.describe ~id payload);
    raw = lazy (Tool_activity.raw payload);
  }

let update t ~task_id tools =
  match t.cached with
  | Some cached when cached.task_id = task_id && cached.tools == tools -> cached.document
  | previous ->
      let old =
        match previous with
        | Some cached when cached.task_id = task_id -> Some cached.document
        | _ -> None
      in
      let document = Hashtbl.create (List.length tools) in
      List.iter
        (fun (id, payload) ->
          let entry =
            match Option.bind old (fun old -> Hashtbl.find_opt old id) with
            | Some entry when entry.payload == payload -> entry
            | _ -> item id payload
          in
          Hashtbl.replace document id entry)
        tools;
      (* Retain only current tools. Decoding occurs when a view requests a representation. *)
      t.cached <- Some { task_id; tools; document };
      document

let lookup document ~id ~payload =
  match Hashtbl.find_opt document id with
  | Some entry when entry.payload == payload -> entry
  | _ -> item id payload

let describe document ~id ~payload = Lazy.force (lookup document ~id ~payload).description
let raw document ~id ~payload = Lazy.force (lookup document ~id ~payload).raw
