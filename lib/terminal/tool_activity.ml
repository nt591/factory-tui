type t = { summary : string; details : string list }

let field name = function
  | `Assoc fields -> Option.value ~default:`Null (List.assoc_opt name fields)
  | _ -> `Null

let text name json = match field name json with `String value -> Some value | _ -> None
let lines text = String.split_on_char '\n' text
let json_text value = Yojson.Basic.pretty_to_string value

let status json =
  let state = Option.value ~default:"status unknown" (text "status" json) in
  match field "exit_code" json with
  | `Int code -> state ^ " / exit " ^ string_of_int code
  | _ -> state

let raw payload =
  try lines (json_text (Yojson.Basic.from_string payload))
  with Yojson.Json_error _ -> lines payload

let describe ~id payload =
  let fallback () =
    { summary = "Tool " ^ id ^ " / unstructured"; details = lines payload }
  in
  try
    let json = Yojson.Basic.from_string payload in
    let identity = Option.value ~default:id (text "id" json) in
    match text "type" json with
    | Some "command_execution" ->
        let command =
          Option.value ~default:"command not supplied" (text "command" json)
        in
        {
          summary = "Command / " ^ status json;
          details =
            ([ "$ " ^ command; "Item: " ^ identity ]
            @
            match text "aggregated_output" json with
            | Some "" -> [ "Output: empty" ]
            | Some output -> "Output:" :: lines output
            | None -> [ "Output: not supplied" ]);
        }
    | Some "mcp_tool_call" ->
        let server = Option.value ~default:"server unknown" (text "server" json)
        and tool = Option.value ~default:"tool unknown" (text "tool" json) in
        let rendered name label =
          match field name json with
          | `Null -> []
          | value -> label :: lines (json_text value)
        in
        {
          summary = "MCP " ^ server ^ "/" ^ tool ^ " / " ^ status json;
          details =
            [ "Item: " ^ identity ]
            @ rendered "arguments" "Arguments:"
            @ rendered "result" "Result:" @ rendered "error" "Error:";
        }
    | Some "file_change" ->
        let changes =
          match field "changes" json with
          | `List values ->
              List.map
                (fun change ->
                  let kind = Option.value ~default:"change" (text "kind" change)
                  and path = Option.value ~default:"path unknown" (text "path" change) in
                  kind ^ " " ^ path)
                values
          | _ -> [ "Changes: not supplied" ]
        in
        { summary = "Files / " ^ status json; details = ("Item: " ^ identity) :: changes }
    | Some kind -> { summary = kind ^ " / " ^ status json; details = raw payload }
    | None -> fallback ()
  with Yojson.Json_error _ -> fallback ()
