type tone = Author of bool | Body | Spacer
type row = { id : string; index : int; text : string; tone : tone }
type document = { rows : row list; anchors : (string * int) list }
type block = { message : Model.message; rows : row list; anchors : (string * int) list }

type cached = {
  task_id : string;
  width : int;
  messages : Model.message list;
  document : document;
  blocks : (string, block) Hashtbl.t;
}

type t = { mutable cached : cached option }

let create () = { cached = None }
let clear t = t.cached <- None
let rows (document : document) = document.rows
let anchors (document : document) = document.anchors

let build_message width (message : Model.message) =
  let body = Text_layout.wrap width (Terminal_text.multiline message.text) in
  let author = Terminal_text.line message.author in
  let heading =
    author
    ^
    if message.queued then " / queued"
    else if message.author = "You" then " / sent"
    else ""
  in
  let heading = Text_layout.wrap_words width heading in
  let heading = if heading = [] then [ "" ] else heading in
  let heading_count = List.length heading in
  (* Header indices end at zero so wrapped author growth cannot renumber body anchors. *)
  let headers =
    List.mapi
      (fun index text ->
        {
          id = message.id;
          index = index - heading_count + 1;
          text;
          tone = Author message.queued;
        })
      heading
  in
  let rows =
    headers
    @ List.mapi
        (fun index text -> { id = message.id; index = index + 1; text; tone = Body })
        body
    @ [ { id = message.id; index = List.length body + 1; text = ""; tone = Spacer } ]
  in
  { message; rows; anchors = List.map (fun row -> (row.id, row.index)) rows }

let build ~previous width messages =
  let blocks = Hashtbl.create (List.length messages) in
  let ordered =
    List.map
      (fun (message : Model.message) ->
        let block =
          match
            Option.bind previous (fun blocks -> Hashtbl.find_opt blocks message.id)
          with
          | Some block when block.message == message -> block
          | _ -> build_message width message
        in
        Hashtbl.replace blocks message.id block;
        block)
      messages
  in
  (* Only current messages enter the new index. Removed history must not accumulate. *)
  ( {
      rows = List.concat_map (fun block -> block.rows) ordered;
      anchors = List.concat_map (fun block -> block.anchors) ordered;
    },
    blocks )

let update t ~task_id ~width messages =
  let width = max 1 width in
  match t.cached with
  | Some cached
    when cached.task_id = task_id && cached.width = width && cached.messages == messages
    ->
      cached.document
  | _ ->
      let previous =
        match t.cached with
        | Some cached when cached.task_id = task_id && cached.width = width ->
            Some cached.blocks
        | _ -> None
      in
      let document, blocks = build ~previous width messages in
      t.cached <- Some { task_id; width; messages; document; blocks };
      document
