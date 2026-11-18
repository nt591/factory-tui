type tone = Author of bool | Body | Spacer
type row = { id : string; index : int; text : string; tone : tone }
type document = { rows : row list; anchors : (string * int) list }

type cached = {
  task_id : string;
  width : int;
  messages : Model.message list;
  document : document;
}

type t = { mutable cached : cached option }

let create () = { cached = None }
let clear t = t.cached <- None
let rows document = document.rows
let anchors document = document.anchors

let clean text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code = 10 then Buffer.add_char buffer '\n'
          else if code < 32 || (code >= 127 && code <= 159) then
            Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let build width messages =
  let rows =
    List.concat_map
      (fun (message : Model.message) ->
        let body = Text_layout.wrap width (clean message.text) in
        {
          id = message.id;
          index = 0;
          text =
            (message.author
            ^
            if message.queued then " / queued"
            else if message.author = "You" then " / sent"
            else "");
          tone = Author message.queued;
        }
        :: (List.mapi
              (fun index text ->
                { id = message.id; index = index + 1; text; tone = Body })
              body
           @ [
               { id = message.id; index = List.length body + 1; text = ""; tone = Spacer };
             ]))
      messages
  in
  { rows; anchors = List.map (fun row -> (row.id, row.index)) rows }

let update t ~task_id ~width messages =
  let width = max 1 width in
  match t.cached with
  | Some cached
    when cached.task_id = task_id && cached.width = width && cached.messages == messages
    ->
      cached.document
  | _ ->
      (* Messages are immutable. A new list invalidates streamed text and delivery labels. *)
      let document = build width messages in
      t.cached <- Some { task_id; width; messages; document };
      document
