type t = {
  mutable query : string;
  mutable search : Literal_search.t;
  mutable matches : string array;
  mutable selected : string option;
  mutable pending_seek : bool;
  mutable cached_messages : Model.message list option;
  membership : (string, int) Hashtbl.t;
}

let create () =
  {
    query = "";
    search = Literal_search.prepare "";
    matches = [||];
    selected = None;
    pending_seek = false;
    cached_messages = None;
    membership = Hashtbl.create 16;
  }

let query t = t.query

let set_query t query =
  if String.length query <= 256 && t.query <> query then (
    t.query <- query;
    t.search <- Literal_search.prepare query;
    t.selected <- None;
    t.cached_messages <- None;
    t.pending_seek <- true)

let clear t =
  t.query <- "";
  t.search <- Literal_search.prepare "";
  t.matches <- [||];
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
              if
                Literal_search.contains t.search message.text
                || Literal_search.contains t.search message.author
              then Some message.id
              else None)
            messages
      in
      let matches = Array.of_list matches in
      Hashtbl.clear t.membership;
      Array.iteri (fun index id -> Hashtbl.replace t.membership id index) matches;
      let selected =
        match t.selected with
        | Some id when Hashtbl.mem t.membership id -> Some id
        | _ -> if Array.length matches = 0 then None else Some matches.(0)
      in
      if selected <> t.selected then t.pending_seek <- true;
      t.selected <- selected;
      t.matches <- matches;
      t.cached_messages <- Some messages

let position t =
  let index =
    Option.bind t.selected (Hashtbl.find_opt t.membership)
    |> Option.fold ~none:0 ~some:(fun index -> index + 1)
  in
  (index, Array.length t.matches)

let move t ~backwards =
  let index, count = position t in
  if count > 0 then (
    let next = if backwards then (index + count - 2) mod count else index mod count in
    t.selected <- Some t.matches.(next);
    t.pending_seek <- true)

let matches t id = Hashtbl.mem t.membership id
let current t = t.selected

let seek t =
  if t.pending_seek then (
    t.pending_seek <- false;
    t.selected)
  else None
