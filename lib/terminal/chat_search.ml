type t = {
  mutable query : string;
  mutable matches : string list;
  mutable selected : string option;
  mutable pending_seek : bool;
  mutable cached_messages : Model.message list option;
  membership : (string, unit) Hashtbl.t;
}

let create () =
  {
    query = "";
    matches = [];
    selected = None;
    pending_seek = false;
    cached_messages = None;
    membership = Hashtbl.create 16;
  }

let query t = t.query

let contains text query =
  let text = String.lowercase_ascii text and query = String.lowercase_ascii query in
  let rec loop i =
    i + String.length query <= String.length text
    && (String.sub text i (String.length query) = query || loop (i + 1))
  in
  loop 0

let set_query t query =
  if String.length query <= 256 && t.query <> query then (
    t.query <- query;
    t.selected <- None;
    t.cached_messages <- None;
    t.pending_seek <- true)

let clear t =
  t.query <- "";
  t.matches <- [];
  t.selected <- None;
  t.pending_seek <- false;
  t.cached_messages <- None;
  Hashtbl.reset t.membership

let sync t messages =
  (* A new immutable list is required when streamed text or authors change. *)
  match t.cached_messages with
  | Some cached when cached == messages -> ()
  | _ ->
      let matches =
        if t.query = "" then []
        else
          List.filter_map
            (fun (message : Model.message) ->
              if contains message.text t.query || contains message.author t.query then
                Some message.id
              else None)
            messages
      in
      Hashtbl.clear t.membership;
      List.iter (fun id -> Hashtbl.replace t.membership id ()) matches;
      let selected =
        match t.selected with
        | Some id when Hashtbl.mem t.membership id -> Some id
        | _ -> ( match matches with [] -> None | id :: _ -> Some id)
      in
      if selected <> t.selected then t.pending_seek <- true;
      t.selected <- selected;
      t.matches <- matches;
      t.cached_messages <- Some messages

let position t =
  let rec index n = function
    | [] -> 0
    | id :: _ when t.selected = Some id -> n
    | _ :: rest -> index (n + 1) rest
  in
  (index 1 t.matches, List.length t.matches)

let move t ~backwards =
  let index, count = position t in
  if count > 0 then (
    let next = if backwards then (index + count - 2) mod count else index mod count in
    t.selected <- Some (List.nth t.matches next);
    t.pending_seek <- true)

let matches t id = Hashtbl.mem t.membership id
let current t = t.selected

let seek t =
  if t.pending_seek then (
    t.pending_seek <- false;
    t.selected)
  else None
