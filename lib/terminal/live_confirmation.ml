open Notty

type action = Run | Cancel
type hit = { x : int; y : int; width : int; action : action }
type view = { image : Notty.image; hits : hit list; readable : bool }

let render ?(policy = Model.Read_only) task ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let readable = cols >= 64 && rows >= 13 && task <> None in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let text = A.(fg white ++ bg background) in
  let warning = A.(fg lightyellow ++ bg background ++ st bold) in
  let line attr value =
    let value =
      String.map (fun c -> if Char.code c < 32 || Char.code c = 127 then ' ' else c) value
    in
    I.(string attr value |> hsnap ~align:`Left (max 0 (cols - 2)))
  in
  let details =
    match task with
    | None -> [ "Task no longer exists. Cancel and select another task." ]
    | Some task ->
        [
          task.Model.id ^ " / " ^ task.title;
          "Model: " ^ task.model;
          ("Workspace: "
          ^ match task.workspace with None -> "missing" | Some w -> w.directory);
          "Thread: " ^ Option.value ~default:"new thread" task.thread_id;
        ]
  in
  let lines =
    if readable then
      [
        "Real Codex process / may incur model usage.";
        "Configured credentials or existing Codex auth may be used.";
        (match policy with
        | Model.Read_only -> "Read-only sandbox requested / no interactive approvals."
        | Model.Workspace_write ->
            "WRITE ACCESS: task workspace / no interactive approvals.");
        "";
      ]
      @ details
      @ [ ""; "[Run / Enter or y]     [Cancel / Escape or n]" ]
    else
      [
        "Live execution requires a larger terminal.";
        "Resize to at least 64 columns and 13 rows.";
        "No run can be confirmed at this size.";
        "Escape or n cancels.";
      ]
  in
  let content = I.vcat (List.map (line text) lines) in
  let canvas = I.(char text ' ' cols rows) in
  let image =
    if cols < 2 || rows < 2 then I.(content </> canvas |> hsnap cols |> vsnap rows)
    else
      let horizontal = String.concat "" (List.init (cols - 2) (fun _ -> "─")) in
      let top =
        I.(
          string warning "╭"
          <|> (string warning (" Confirm live run " ^ horizontal)
              |> hsnap ~align:`Left (cols - 2))
          <|> string warning "╮")
      in
      let side = I.uchar warning (Uchar.of_int 0x2502) 1 (rows - 2) in
      let middle =
        I.(
          side
          <|> (content
              |> hsnap ~align:`Left (cols - 2)
              |> vsnap ~align:`Top (rows - 2)
              </> char text ' ' (cols - 2) (rows - 2))
          <|> side)
      in
      I.(top <-> middle <-> string warning ("╰" ^ horizontal ^ "╯"))
  in
  let hits =
    if readable then
      [
        { x = 1; y = 10; width = 20; action = Run };
        { x = 23; y = 10; width = 26; action = Cancel };
      ]
    else []
  in
  { image; hits; readable }
