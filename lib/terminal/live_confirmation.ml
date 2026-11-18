open Notty

type action = Run | Cancel
type hit = { x : int; y : int; width : int; action : action }
type view = { image : Notty.image; hits : hit list; readable : bool }

let clean value =
  let buffer = Buffer.create (String.length value) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code < 32 || (code >= 127 && code <= 159) then Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () value;
  Buffer.contents buffer

let disclosure ~policy task =
  [
    "Real Codex process / may incur model usage.";
    "Configured credentials or existing Codex auth may be used.";
    (match policy with
    | Model.Read_only -> "Read-only sandbox requested / no interactive approvals."
    | Model.Workspace_write -> "WRITE ACCESS: workspace + temp directories; no approvals.");
    "";
  ]
  @
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

let wrapped ~policy task width =
  List.concat_map
    (fun text -> Text_layout.wrap (max 1 (width - 2)) (clean text))
    (disclosure ~policy task)

let required_height ?(policy = Model.Read_only) task ~width =
  max 13 (List.length (wrapped ~policy task width) + 4)

let render ?(policy = Model.Read_only) task ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let details = wrapped ~policy task cols in
  let required = required_height ~policy task ~width:cols in
  let readable =
    cols >= 64 && rows >= required && task <> None
    && List.for_all (fun row -> I.width (I.string A.empty row) <= cols - 2) details
  in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let text = A.(fg white ++ bg background) in
  let warning = A.(fg lightyellow ++ bg background ++ st bold) in
  let line attr value =
    I.(string attr (clean value) |> hsnap ~align:`Left (max 0 (cols - 2)))
  in
  let button_y = List.length details + 2 in
  let lines =
    if readable then details @ [ ""; "[Run / Enter or y]     [Cancel / Escape or n]" ]
    else
      List.concat_map
        (fun value -> Text_layout.wrap (max 1 (cols - 2)) value)
        [
          "Live execution requires a larger terminal.";
          Printf.sprintf
            "At this width, all details need %d rows and at least 64 columns." required;
          "No run can be confirmed while details are hidden.";
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
        { x = 1; y = button_y; width = 20; action = Run };
        { x = 23; y = button_y; width = 26; action = Cancel };
      ]
    else []
  in
  { image; hits; readable }
