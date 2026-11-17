open Model

type decoded = { event : event option; raw : Yojson.Basic.t }

exception Invalid

let decode line =
  try
    let raw = Yojson.Basic.from_string line in
    let field value key =
      match Yojson.Basic.Util.member key value with
      | `String value -> value
      | _ -> raise Invalid
    in
    let event =
      match field raw "type" with
      | "thread.started" -> Some (Thread_started (field raw "thread_id"))
      | "turn.started" -> Some Turn_started
      | "turn.completed" -> Some Turn_completed
      | "turn.failed" ->
          Some (Failed (field (Yojson.Basic.Util.member "error" raw) "message"))
      | "error" -> Some (Failed (field raw "message"))
      | "item.started" | "item.updated" | "item.completed" -> (
          let item = Yojson.Basic.Util.member "item" raw in
          match field item "type" with
          | "agent_message" -> Some (Message (field item "id", field item "text"))
          | "command_execution" | "mcp_tool_call" | "file_change" ->
              Some (Tool (field item "id", Yojson.Basic.to_string item))
          | _ -> None)
      | _ -> None
    in
    Ok { event; raw }
  with Invalid | Yojson.Json_error _ | Yojson.Basic.Util.Type_error _ ->
    Error "Invalid harness event. Source content was not printed."
