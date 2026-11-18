open Notty

type action = Run | Cancel
type hit = { x : int; y : int; width : int; action : action }
type view = { image : Notty.image; hits : hit list; readable : bool; content_rows : int }
type prepared = { disclosed : string list; width : int; rows : string array; fits : bool }

type t = {
  mutable prepared : prepared option;
  mutable layout : (string list * int * int) option;
  mutable offset : int;
  mutable capacity : int;
  mutable total : int;
  mutable visited : (int * int) list;
}

let create () =
  { prepared = None; layout = None; offset = 0; capacity = 0; total = 0; visited = [] }

let clear_coverage t =
  t.layout <- None;
  t.offset <- 0;
  t.visited <- []

let reset t =
  t.prepared <- None;
  clear_coverage t

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

let prepare viewport ~policy task width =
  let width = max 1 width in
  let disclosed = disclosure ~policy task in
  match viewport.prepared with
  | Some prepared when prepared.width = width && prepared.disclosed = disclosed ->
      prepared
  | _ ->
      let rows =
        List.concat_map
          (fun text -> Text_layout.wrap (max 1 (width - 2)) (Terminal_text.line text))
          disclosed
        |> Array.of_list
      in
      let fits =
        Array.for_all (fun row -> I.width (I.string A.empty row) <= width - 2) rows
      in
      let prepared = { disclosed; width; rows; fits } in
      viewport.prepared <- Some prepared;
      prepared

let required_height ?(policy = Model.Read_only) ?viewport task ~width =
  let viewport = Option.value ~default:(create ()) viewport in
  max 13 (Array.length (prepare viewport ~policy task width).rows + 4)

let can_confirm t ~policy task =
  match t.layout with
  | Some (disclosed, cols, rows) ->
      cols >= 64 && rows >= 13 && task <> None && reviewed t
      && disclosure ~policy task = disclosed
  | None -> false

let render ?(policy = Model.Read_only) ?viewport task ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let viewport = Option.value ~default:(create ()) viewport in
  let prepared = prepare viewport ~policy task cols in
  let layout = (prepared.disclosed, cols, rows) in
  if viewport.layout <> Some layout then (
    clear_coverage viewport;
    viewport.layout <- Some layout);
  viewport.total <- Array.length prepared.rows;
  viewport.capacity <- max 0 (rows - 4);
  move viewport viewport.offset;
  let usable = cols >= 64 && rows >= 13 && task <> None && prepared.fits in
  if usable then
    visit viewport viewport.offset
      (min viewport.total (viewport.offset + viewport.capacity));
  let readable = usable && reviewed viewport in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let text = A.(fg white ++ bg background) in
  let warning = A.(fg lightyellow ++ bg background ++ st bold) in
  let line attr value =
    I.(string attr (Terminal_text.line value) |> hsnap ~align:`Left (max 0 (cols - 2)))
  in
  let button_y = rows - 2 in
  let lines =
    if usable then
      List.init
        (min viewport.capacity (viewport.total - viewport.offset))
        (fun index -> prepared.rows.(viewport.offset + index))
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
