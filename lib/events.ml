open Model

let decode line =
  try
    let json = Yojson.Basic.from_string line in
    let field key =
      match Yojson.Basic.Util.member key json with
      | `String value when value <> "" -> value
      | _ -> failwith ("Missing string field: " ^ key)
    in
    let event =
      match field "type" with
      | "turn.started" -> Turn_started
      | "thread.started" -> Thread_started (field "thread_id")
      | "message" -> Message (field "item_id", field "text")
      | "tool" -> Tool (field "item_id", field "text")
      | "turn.completed" -> Turn_completed
      | "turn.failed" -> Failed (field "text")
      | "input.requested" -> Input_requested (field "text")
      | "run.interrupted" -> Interrupted
      | "process.exited" -> (
          match Yojson.Basic.Util.member "code" json with
          | `Int code -> Exited code
          | _ -> failwith "Missing integer field: code")
      | _ -> failwith "Unknown event type."
    in
    Ok { task_id = field "task_id"; run_id = field "run_id"; event }
  with
  | Yojson.Json_error _ -> Error "Invalid event JSON."
  | Failure error -> Error error
  | Yojson.Basic.Util.Type_error _ -> Error "Event must be a JSON object."

(* The input file is a replay source, not an agent execution interface. *)
type source = {
  fd : Unix.file_descr;
  mutable pending : string;
  mutable discarded : bool;
  mutable closed : bool;
}

let open_source path =
  let fd = Unix.openfile path [ Unix.O_RDONLY; Unix.O_NONBLOCK ] 0 in
  let kind = (Unix.fstat fd).Unix.st_kind in
  if kind <> Unix.S_REG && kind <> Unix.S_FIFO then (
    Unix.close fd;
    invalid_arg "Event source must be a regular file or FIFO.");
  { fd; pending = ""; discarded = false; closed = false }

let poll source =
  if source.closed then invalid_arg "Event source is closed.";
  let bytes = Bytes.create 8192 in
  let count =
    try Unix.read source.fd bytes 0 8192
    with Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> 0
  in
  let data = source.pending ^ Bytes.sub_string bytes 0 count in
  let pieces = String.split_on_char '\n' data in
  let complete, pending =
    match List.rev pieces with tail :: rest -> (List.rev rest, tail) | [] -> ([], "")
  in
  source.pending <- pending;
  let results =
    List.filter_map
      (fun line ->
        if source.discarded then (
          source.discarded <- false;
          None)
        else if String.length line > 65536 then Some (Error "Event line exceeds 64 KiB.")
        else if String.trim line = "" then None
        else Some (decode line))
      complete
  in
  if String.length source.pending > 65536 then (
    source.pending <- "";
    source.discarded <- true;
    results @ [ Error "Event line exceeds 64 KiB." ])
  else results

let encode (envelope : envelope) =
  let fields =
    match envelope.event with
    | Turn_started -> [ ("type", `String "turn.started") ]
    | Thread_started id ->
        [ ("type", `String "thread.started"); ("thread_id", `String id) ]
    | Message (id, text) ->
        [ ("type", `String "message"); ("item_id", `String id); ("text", `String text) ]
    | Tool (id, text) ->
        [ ("type", `String "tool"); ("item_id", `String id); ("text", `String text) ]
    | Turn_completed -> [ ("type", `String "turn.completed") ]
    | Failed text -> [ ("type", `String "turn.failed"); ("text", `String text) ]
    | Input_requested text ->
        [ ("type", `String "input.requested"); ("text", `String text) ]
    | Interrupted -> [ ("type", `String "run.interrupted") ]
    | Exited code -> [ ("type", `String "process.exited"); ("code", `Int code) ]
  in
  Yojson.Basic.to_string
    (`Assoc
       ([ ("task_id", `String envelope.task_id); ("run_id", `String envelope.run_id) ]
       @ fields))

let close_source source =
  if not source.closed then (
    source.closed <- true;
    Unix.close source.fd)
