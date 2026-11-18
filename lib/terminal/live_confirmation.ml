open Notty

type action = Run | Cancel
type hit = { x : int; y : int; width : int; action : action }
type view = { image : Notty.image; hits : hit list; readable : bool; content_rows : int }

type t = {
  mutable layout : (string list * int * int) option;
  mutable offset : int;
  mutable capacity : int;
  mutable total : int;
  mutable visited : (int * int) list;
}

let create () = { layout = None; offset = 0; capacity = 0; total = 0; visited = [] }

let reset t =
  t.layout <- None;
  t.offset <- 0;
  t.visited <- []

let move t offset = t.offset <- max 0 (min offset (max 0 (t.total - t.capacity)))
let scroll t delta = move t (t.offset + delta)

let key t (key, mods) =
  match (key, mods) with
  | (`ASCII 'j' | `Arrow `Down), [] -> scroll t 1
  | (`ASCII 'k' | `Arrow `Up), [] -> scroll t (-1)
  | (`Page `Down | `ASCII 'f'), [] -> scroll t (max 1 t.capacity)
  | (`Page `Up | `ASCII 'b'), [] -> scroll t (-max 1 t.capacity)
  | `ASCII 'd', [ `Ctrl ] -> scroll t (max 1 (t.capacity / 2))
  | `ASCII 'u', [ `Ctrl ] -> scroll t (-max 1 (t.capacity / 2))
  | `ASCII 'f', [ `Ctrl ] -> scroll t (max 1 t.capacity)
  | `ASCII 'b', [ `Ctrl ] -> scroll t (-max 1 t.capacity)
  | (`Home | `ASCII 'g'), [] -> move t 0
  | (`End | `ASCII 'G'), [] -> move t t.total
  | _ -> ()

(* Every disclosure row must be shown. A jump to the last page can leave a gap. *)
let visit t first last =
  let intervals = List.sort compare ((first, last) :: t.visited) in
  t.visited <-
    List.rev
      (List.fold_left
         (fun merged (first, last) ->
           match merged with
           | (start, stop) :: rest when first <= stop -> (start, max stop last) :: rest
           | _ -> (first, last) :: merged)
         [] intervals)

let reviewed t = t.visited = [ (0, t.total) ]

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

let can_confirm t ~policy task =
  match t.layout with
  | Some (disclosed, cols, rows) ->
      cols >= 64 && rows >= 13 && task <> None && reviewed t
      && disclosure ~policy task = disclosed
  | None -> false

let render ?(policy = Model.Read_only) ?viewport task ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let details = wrapped ~policy task cols in
  let viewport = Option.value ~default:(create ()) viewport in
  let layout = (disclosure ~policy task, cols, rows) in
  if viewport.layout <> Some layout then (
    reset viewport;
    viewport.layout <- Some layout);
  viewport.total <- List.length details;
  viewport.capacity <- max 0 (rows - 4);
  move viewport viewport.offset;
  let usable =
    cols >= 64 && rows >= 13 && task <> None
    && List.for_all (fun row -> I.width (I.string A.empty row) <= cols - 2) details
  in
  if usable then
    visit viewport viewport.offset
      (min viewport.total (viewport.offset + viewport.capacity));
  let readable = usable && reviewed viewport in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let text = A.(fg white ++ bg background) in
  let warning = A.(fg lightyellow ++ bg background ++ st bold) in
  let line attr value =
    I.(string attr (clean value) |> hsnap ~align:`Left (max 0 (cols - 2)))
  in
  let button_y = rows - 2 in
  let lines =
    if usable then
      List.filteri
        (fun index _ ->
          index >= viewport.offset && index - viewport.offset < viewport.capacity)
        details
    else
      List.concat_map
        (fun value -> Text_layout.wrap (max 1 (cols - 2)) value)
        [
          "Live execution requires at least 64 columns and 13 rows.";
          "Resize to review the details. No run can be confirmed here.";
          "Escape or n cancels.";
        ]
  in
  let content = I.vcat (List.map (line text) lines) in
  let content =
    if usable then
      let progress =
        Printf.sprintf "%d-%d/%d · j/k scroll · g/G edges · %s" (viewport.offset + 1)
          (min viewport.total (viewport.offset + viewport.capacity))
          viewport.total
          (if readable then "reviewed" else "review all details")
      in
      let buttons =
        if readable then "[Run / Enter or y]     [Cancel / Escape or n]"
        else "[Review all details]   [Cancel / Escape or n]"
      in
      I.(
        content
        |> vsnap ~align:`Top viewport.capacity
        <-> line warning progress
        <-> line (if readable then warning else text) buttons)
    else content
  in
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
    if usable then
      (if readable then [ { x = 1; y = button_y; width = 20; action = Run } ] else [])
      @ [ { x = 23; y = button_y; width = 26; action = Cancel } ]
    else []
  in
  { image; hits; readable; content_rows = (if usable then viewport.capacity else 0) }
