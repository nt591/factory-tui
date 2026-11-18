open Notty
open Model
open Controller

type rect = { x : int; y : int; w : int; h : int }
type hit = { rect : rect; action : action }
type input_hit = { rect : rect; input : Controller.input; action : Input_controls.action }

type frame = {
  image : image;
  hits : hit list;
  input_controls : input_hit list;
  sidebar : (rect * int) option;
  columns : (rect * Model.state * int * int) list;
  panes : (rect * Controller.focus) list;
  scroll_panes : (rect * Controller.focus) list;
  modal_scroll : rect option;
}

let color_rgb r g b = A.rgb_888 ~r ~g ~b
let background = color_rgb 19 23 32
let panel = color_rgb 25 31 42
let muted = color_rgb 129 143 161
let text = color_rgb 218 227 237
let accent = color_rgb 118 190 218

let state_color = function
  | Queued -> muted
  | Working -> accent
  | Needs_you -> color_rgb 239 185 99
  | Ready | Done -> color_rgb 147 203 154

let attr color = A.(fg color ++ bg panel)
let emphasis color = A.(attr color ++ st bold)

let line cols a text =
  I.(string a (clean ~newlines:false text) |> hsnap ~align:`Left cols)

let fit w h image =
  I.(image |> hsnap ~align:`Left (max 0 w) |> vsnap ~align:`Top (max 0 h))

let block cols rows a = I.char a ' ' (max 0 cols) (max 0 rows)
let glyph a s = I.string a s
let wrap cols text = Text_layout.wrap cols (clean text)
let wrap_title cols text = Text_layout.wrap_words cols (clean ~newlines:false text)

let border ?(footer = "") ?(section = false) cols rows ~title ~color ~focused content =
  if cols < 2 || rows < 2 then fit cols rows content
  else
    let a = if focused then emphasis color else attr muted in
    let strong = section && focused in
    let tl, tr, bl, br, bar, vertical =
      if strong then ("┏", "┓", "┗", "┛", "━", 0x2503)
      else ("╭", "╮", "╰", "╯", "─", 0x2502)
    in
    let horizontal = String.concat "" (List.init (cols - 2) (fun _ -> bar)) in
    let edge left right label =
      I.(
        glyph a left
        <|> (glyph a (bar ^ " " ^ clean ~newlines:false label ^ " " ^ horizontal)
            |> hsnap ~align:`Left (cols - 2))
        <|> glyph a right)
    in
    let top = edge tl tr title in
    let bottom =
      if footer = "" then glyph a (bl ^ horizontal ^ br) else edge bl br footer
    in
    let middle =
      I.(
        uchar a (Uchar.of_int vertical) 1 (rows - 2)
        <|> (fit (cols - 2) (rows - 2) content </> block (cols - 2) (rows - 2) (attr text))
        <|> uchar a (Uchar.of_int vertical) 1 (rows - 2))
    in
    I.(top <-> middle <-> bottom)

let hit_at frame x y =
  List.find_opt
    (fun ({ rect; _ } : hit) ->
      x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h)
    frame.hits
  |> Option.map (fun (hit : hit) -> hit.action)

let render t ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let canvas = ref (block cols rows A.(bg background)) and hits = ref [] in
  let paint x y image = canvas := I.(pad ~l:x ~t:y image </> !canvas) in
  let hit x y w h action =
    let w = min w (cols - x) and h = min h (rows - y) in
    if x >= 0 && y >= 0 && w > 0 && h > 0 then
      hits := { rect = { x; y; w; h }; action } :: !hits
  in
  let input_controls = ref [] in
  let sidebar = ref None and column_regions = ref [] and panes = ref [] in
  let scroll_panes = ref [] in
  let scroll_region (r : rect) focus skipped =
    let content =
      { x = r.x + 1; y = r.y + 1 + skipped; w = r.w - 2; h = r.h - 2 - skipped }
    in
    if content.w > 0 && content.h > 0 then
      scroll_panes := (content, focus) :: !scroll_panes
  in
  let modal_scroll = ref None in
  let mode =
    match t.live_config with
    | Some config -> Menu_content.Live (Live_runner.policy config)
    | None when t.fake_harness -> Menu_content.Fake
    | None when t.external_events -> Menu_content.Replay
    | None -> Menu_content.Simulation
  in
  let header = Session_header.text ~width:cols ~mode ~paused:t.paused in
  paint 0 0 (line cols A.(fg accent ++ bg background ++ st bold) header);
  let sidebar_width = if cols >= 145 && not t.zoom then 22 else 0 in
  let main_width = cols - sidebar_width in
  let repository_labels = Repository_labels.create (repositories t) in
  let repository_label = Repository_labels.label repository_labels in
  let board_tasks = visible t in
  let states = if t.archive then [ Done ] else Board_lanes.states in
  let tabs =
    Board_tabs.make ~width:cols ~archive:t.archive
      ~count:(List.length (List.filter (fun (task : task) -> task.state = Done) t.tasks))
  in
  List.iter
    (fun (item : Board_tabs.item) ->
      paint item.x 1
        (line item.width (if item.active then emphasis accent else attr muted) item.text);
      hit item.x 1 item.width 1
        (match item.destination with Board -> Session_board | Archive -> Archive_view))
    tabs;
  let meter_x = max sidebar_width (Board_tabs.extent tabs) in
  let meter_width = max 0 ((cols - meter_x) / List.length states) in
  if meter_width >= 10 then
    List.iteri
      (fun i state ->
        let count =
          List.length
            (List.filter
               (fun (task : task) -> Board_lanes.contains state task)
               board_tasks)
        in
        paint
          (meter_x + (i * meter_width))
          1
          (line meter_width
             (emphasis (state_color state))
             (Printf.sprintf " %02d  %s" count (label state))))
      states;
  let summary =
    Board_summary.make ~width:main_width ~archive:t.archive
      ~repository:(Option.map repository_label t.repository)
      ~count:(List.length board_tasks) ~query:t.query
      ~hidden:
        (selected t <> None
        && not (List.exists (fun (task : task) -> task.id = t.selected) board_tasks))
  in
  paint sidebar_width 2 (line main_width (attr muted) summary.text);
  List.iter
    (fun (item : Board_summary.hit) ->
      hit (sidebar_width + item.x) 2 item.width 1
        (match item.action with
        | Board_summary.Search -> Begin_search
        | Board_summary.Reveal_selected -> Reveal_selected))
    summary.hits;
  let body_y = 3 and body_h = max 0 (rows - 6) in
  let task = selected t in
  let detail_visible = ref false in
  let composer_editor_visible = ref false in
  let conversation r =
    let draft_rows = max 1 (List.length (wrap (max 1 (r.w - 6)) (draft t))) in
    let composer_height =
      if r.h >= 10 && task <> None then
        min (max 4 (min 8 (draft_rows + 3))) (max 4 (r.h / 2))
      else 0
    in
    let chat_height = r.h - composer_height in
    let inner = max 1 (r.w - 4) in
    let title, rows, anchors =
      match task with
      | None ->
          Chat_layout.clear t.chat_layout;
          let rows =
            List.map
              (fun text -> { Chat_layout.id = ""; index = 0; text; tone = Spacer })
              (if t.live_config = None then [ "Select a task. Enter or e expands it." ]
               else
                 [
                   "A task's conversation will appear here.";
                   "Create a workspace task with W or n.";
                   "Messages and drafts are saved to your configured SQLite database.";
                 ])
          in
          ("Conversation", rows, List.map (fun _ -> ("", 0)) rows)
      | Some task ->
          Chat_search.sync t.chat_search task.messages;
          let document =
            Chat_layout.update t.chat_layout ~task_id:task.id ~width:inner task.messages
          in
          ( task.id ^ " / " ^ label task.state ^ " / conversation",
            Chat_layout.rows document,
            Chat_layout.anchors document )
    in
    let searching = t.input = Chat_search || Chat_search.query t.chat_search <> "" in
    let available = max 0 (chat_height - 2 - if searching then 1 else 0) in
    if available > 0 then detail_visible := true;
    if t.focus = Conversation then t.page_rows <- max 1 available;
    let view =
      Chat_viewport.update t.chat_viewport ~task_id:t.selected ~rows:anchors
        ~height:available
        ~distance:
          (if t.focus = Conversation then t.scroll
           else Pane_scroll.position t.pane_scroll Chat)
        ~seek:(Chat_search.seek t.chat_search)
    in
    if available > 0 then (
      Pane_scroll.remember t.pane_scroll Chat view.distance;
      if t.focus = Conversation then t.scroll <- view.distance);
    let title =
      title ^ if view.following then "" else " / reading history · End follows"
    in
    let position =
      Chat_position.make ~width:(r.w - 5) ~height:available ~total:(List.length rows) view
    in
    let rows = Chat_viewport.visible_rows view ~height:available rows in
    let content =
      I.vcat
        (List.map
           (fun (row : Chat_layout.row) ->
             let color =
               match row.tone with
               | Author true -> state_color Needs_you
               | Author false -> accent
               | Body -> text
               | Spacer -> muted
             in
             let attribute =
               match row.id with
               | id when Chat_search.current t.chat_search = Some id ->
                   A.(attr color ++ bg (color_rgb 38 57 72) ++ st bold)
               | id when Chat_search.matches t.chat_search id ->
                   A.(attr color ++ st underline)
               | _ -> attr color
             in
             I.hpad 1 1 (line inner attribute row.text))
           rows)
    in
    paint r.x r.y
      (border ~section:true r.w chat_height ~title ~footer:position.text ~color:accent
         ~focused:(t.focus = Conversation)
         (if not searching then content
          else
            let position, count = Chat_search.position t.chat_search in
            let description =
              Search_banner.text ~width:(r.w - 2)
                ~query:(Chat_search.query t.chat_search)
                ~editing:(t.input = Chat_search) ~position ~count
            in
            I.(line (r.w - 2) (emphasis accent) description <-> content)));
    panes := ({ r with h = chat_height }, Conversation) :: !panes;
    scroll_region { r with h = chat_height } Conversation (if searching then 1 else 0);
    hit r.x r.y r.w chat_height (Focus Conversation);
    Option.iter
      (fun (offset, width) ->
        hit (r.x + 3 + offset) (r.y + chat_height - 1) width 1 Follow_chat)
      position.latest;
    if composer_height > 0 then (
      let task = Option.get task in
      let editing = t.input = Compose in
      let preview =
        if task.state = Done then "Accepted task / chat history is read-only"
        else if draft t = "" then "Write a reply…  i to compose"
        else draft t
      in
      let instructions = Composer_guidance.text ~width:inner ~mode ~editing task in
      let capacity = composer_height - 3 in
      if editing && task.state <> Done && capacity > 0 && inner >= 4 then
        composer_editor_visible := true;
      let window =
        Composer_layout.make ~width:inner ~capacity ~preview
          ~editor:(if editing && task.state <> Done then Some t.editor else None)
      in
      let composer =
        I.vcat
          ( List.map (line inner (attr (if editing then text else muted))) window.rows
          |> fun images ->
            [ fit inner capacity (I.vcat images); line inner (attr muted) instructions ]
          )
        |> I.hpad 1 1
      in
      paint r.x (r.y + chat_height)
        (border ~section:true r.w composer_height
           ~title:
             (if task.state = Done then
                Acceptance_summary.title ~width:(r.w - 5)
                  (Acceptance_summary.make ~draft:(draft t) task)
              else Queue_summary.title ~width:(r.w - 5) task)
           ~footer:
             (if task.state = Done then ""
              else Composer_layout.position ~width:(r.w - 5) window)
           ~color:accent ~focused:editing composer);
      if task.state <> Done then
        hit r.x (r.y + chat_height) r.w composer_height Begin_compose)
  in
  let activity r =
    let inner = max 1 (r.w - 4) in
    let tools =
      match task with
      | None ->
          Tool_cache.clear t.tool_cache;
          None
      | Some task -> Some (Tool_cache.update t.tool_cache ~task_id:task.id task.tools)
    in
    let rows =
      Activity_content.lines ?tools ~now:(Unix.gettimeofday ()) ~expanded:t.tools_expanded
        ~raw:t.raw_tools
        ~waiting:(List.mem t.selected t.live_waiting_tasks)
        task
      |> List.concat_map (wrap inner)
    in
    let capacity = max 0 (r.h - 2) in
    if capacity > 0 then detail_visible := true;
    let requested =
      if t.focus = Activity then t.scroll else Pane_scroll.position t.pane_scroll Activity
    in
    let window =
      Board_window.make ~manual:true ~capacity ~selected:0 ~scroll:requested rows
    in
    let offset = window.offset in
    if capacity > 0 then (
      Pane_scroll.remember t.pane_scroll Activity offset;
      if t.focus = Activity then (
        t.page_rows <- max 1 capacity;
        t.scroll <- offset));
    let footer =
      let cue = Board_window.cue window in
      if cue = "" then "" else "rows " ^ cue
    in
    let content =
      I.vcat
        (window.items |> List.map (fun row -> I.hpad 1 1 (line inner (attr muted) row)))
    in
    paint r.x r.y
      (border ~section:true ~footer r.w r.h
         ~title:
           ((match task with None -> "Task" | Some task -> task.id)
           ^ " / activity"
           ^ if t.activity_expanded then " / expanded · Esc returns" else " / e expands")
         ~color:accent ~focused:(t.focus = Activity) content);
    panes := (r, Activity) :: !panes;
    scroll_region r Activity 0;
    hit r.x r.y r.w r.h (Focus Activity)
  in
  let details r =
    if r.w >= 70 then (
      let left = r.w * 2 / 3 in
      conversation { r with w = left };
      activity { r with x = r.x + left; w = r.w - left })
    else if r.h >= 16 then (
      let top = r.h * 2 / 3 in
      conversation { r with h = top };
      activity { r with y = r.y + top; h = r.h - top })
    else if t.focus = Activity then activity r
    else conversation r
  in
  let board r =
    t.board_list <- r.w < 88 || t.archive;
    panes := (r, Board) :: !panes;
    if t.board_list then scroll_region r Board 0;
    let tasks = visible t in
    if tasks = [] then (
      let guidance =
        Board_guidance.empty ~live:(t.live_config <> None) ~has_tasks:(t.tasks <> [])
          ~archived:t.archive
          ~filtered:(t.query <> "" || t.repository <> None)
      in
      let inner = max 1 (r.w - 4) in
      let lines = List.concat_map (wrap_title inner) guidance.lines in
      let content =
        I.vcat
          ([ line inner (emphasis accent) guidance.title; line inner (attr muted) "" ]
          @ List.map (line inner (attr text)) lines
          @ [ line inner (emphasis accent) guidance.button ])
        |> I.hpad 1 1
      in
      paint r.x r.y
        (border ~section:true r.w r.h
           ~title:(if t.archive then "Archive" else "Session board")
           ~color:accent ~focused:(t.focus = Board) content);
      if r.h > 3 && r.w > 4 then
        (* The button exists only if its actual row is inside the pane. *)
        let actual_row = List.length lines + 2 in
        if actual_row < r.h - 2 then
          hit (r.x + 2)
            (r.y + 1 + actual_row)
            (r.w - 4) 1
            (match guidance.action with
            | Board_guidance.Create_workspace -> Begin_workspace
            | Board_guidance.Create_demo -> Begin_new
            | Board_guidance.Clear_filters | Board_guidance.Open_board -> Session_board))
    else if r.w < 88 || t.archive then (
      let content_width = max 1 (r.w - 2) in
      let capacity = max 0 (r.h - 2) in
      if t.focus = Board then t.page_rows <- max 1 capacity;
      let selected_index =
        let rec find i = function
          | [] -> 0
          | (task : task) :: _ when task.id = t.selected -> i
          | _ :: rest -> find (i + 1) rest
        in
        find 0 tasks
      in
      let window =
        Board_window.make ~capacity ~selected:selected_index ~scroll:t.board_scroll tasks
      in
      let tasks = window.items in
      let rows =
        List.mapi
          (fun i (task : task) ->
            let a =
              if task.id = t.selected then A.(emphasis accent ++ bg (color_rgb 38 57 72))
              else attr text
            in
            hit (r.x + 1) (r.y + 1 + i) content_width 1 (Select task.id);
            line content_width a
              (Task_row.text
                 ~updates:(Task_updates.count t.task_updates task.id)
                 ~width:content_width ~selected:(task.id = t.selected) task))
          tasks
      in
      let title =
        let name = if t.archive then "Archive" else "Tasks" in
        if Board_window.cue window = "" then name ^ " / click to focus / Enter opens"
        else name ^ " / click · " ^ Board_window.cue window ^ " · Enter opens"
      in
      paint r.x r.y
        (border ~section:true r.w r.h ~title ~color:accent ~focused:(t.focus = Board)
           (I.vcat rows)))
    else (
      paint r.x r.y
        (border ~section:true r.w r.h ~title:"Board / h l: lanes / Enter: chat"
           ~color:accent ~focused:(t.focus = Board) I.empty);
      hit r.x r.y r.w 1 (Focus Board);
      let r = { x = r.x + 1; y = r.y + 1; w = r.w - 2; h = r.h - 2 } in
      let lane_count = List.length Board_lanes.states in
      let col_w = r.w / lane_count in
      List.iteri
        (fun column state ->
          let x = r.x + (column * col_w) in
          let w = if column = lane_count - 1 then r.w - (column * col_w) else col_w in
          let items =
            List.filter (fun (task : task) -> Board_lanes.contains state task) tasks
          in
          let capacity = max 0 (r.h / 7) in
          if t.focus = Board then t.page_rows <- max 1 capacity;
          let selected_index =
            let rec find i = function
              | [] -> 0
              | (task : task) :: _ when task.id = t.selected -> i
              | _ :: rest -> find (i + 1) rest
            in
            find 0 items
          in
          let window =
            Board_window.make ~capacity ~selected:selected_index
              ~manual:(Column_scroll.position t.column_scroll state <> None)
              ~scroll:(Column_scroll.offset t.column_scroll state)
              items
          in
          column_regions :=
            ( { x; y = r.y; w; h = r.h },
              state,
              window.offset,
              max 0 (List.length items - max 1 capacity) )
            :: !column_regions;
          let shown = window.items in
          let cards =
            List.mapi
              (fun index (task : task) ->
                let selected = task.id = t.selected in
                let a =
                  if selected then A.(fg text ++ bg (color_rgb 38 57 72)) else attr text
                in
                let title_rows =
                  wrap_title (max 1 (w - 8)) task.title
                  |> Text_layout.limit_rows ~width:(max 1 (w - 8)) ~height:2
                in
                let title_image =
                  I.vcat (List.map (fun title -> line (w - 6) a title) title_rows)
                  |> fit (w - 6) 2
                in
                let card =
                  I.vcat
                    [
                      title_image;
                      line (w - 6) (attr muted)
                        (Text_layout.ellipsize
                           (max 1 (w - 6))
                           (clean ~newlines:false (repository_label task.repository)));
                      line (w - 6) (attr muted)
                        (Text_layout.ellipsize
                           (max 1 (w - 6))
                           (Task_attention.card_text
                              ~updates:(Task_updates.count t.task_updates task.id)
                              task));
                    ]
                  |> I.hpad 1 1
                in
                hit (x + 1) (r.y + 1 + (index * 7)) (w - 2) 6 (Select task.id);
                let title = task.id ^ if selected then " ◂" else "" in
                I.(
                  border (w - 2) 6 ~title ~color:(state_color state)
                    ~focused:(selected && t.focus = Board)
                    card
                  <-> block (w - 2) 1 (attr muted)))
              shown
          in
          let content =
            if items = [] then line (w - 2) (attr muted) "  No tasks"
            else if shown = [] then line (w - 2) (attr muted) "  Resize to show cards"
            else I.vcat cards
          in
          let title =
            let running =
              List.length (List.filter (fun (task : task) -> task.state = Working) items)
            in
            Printf.sprintf "%s %d%s%s" (label state) (List.length items)
              (if Board_window.cue window = "" then ""
               else " / " ^ Board_window.cue window)
              (if state = Working then Printf.sprintf " / %d running" running else "")
          in
          paint x r.y
            (* The board supplies the bottom edge, so this row can show the last card. *)
            (border w (r.h + 1) ~title ~color:(state_color state)
               ~focused:
                 (t.focus = Board
                 &&
                 match task with
                 | Some task -> Board_lanes.contains state task
                 | None -> false)
               content
            |> fit w r.h))
        Board_lanes.states)
  in
  if sidebar_width > 0 then (
    let pinned =
      [
        ("Session board", Session_board);
        ("Archive", Archive_view);
        ((if t.live_config = None then "+ Demo task" else "+ New task"), Begin_new);
        ("+ Workspace task", Begin_workspace);
        ("? Help / settings", Help);
        ("", Help);
        ("REPOSITORIES", Help);
      ]
    in
    let repositories =
      ("All repositories", Repository None)
      :: List.map
           (fun repo -> (repository_label repo, Repository (Some repo)))
           (repositories t)
    in
    let selected =
      let rec find index = function
        | [] -> 0
        | (_, Repository repo) :: _ when repo = t.repository -> index
        | _ :: rest -> find (index + 1) rest
      in
      find 0 repositories
    in
    let window =
      Sidebar_window.make ~height:body_h ~selected ~scroll:t.sidebar_scroll ~pinned
        repositories
    in
    let entries = window.pinned @ window.repositories.items in
    let content =
      I.vcat
        (List.mapi
           (fun index (title, action) ->
             let active =
               match action with
               | Session_board -> (not t.archive) && t.repository = None
               | Archive_view -> t.archive
               | Repository repo -> t.repository = repo
               | _ -> false
             in
             let a =
               if active then A.(fg accent ++ bg (color_rgb 38 57 72)) else attr muted
             in
             if title <> "" && title <> "REPOSITORIES" then
               hit 1 (body_y + 1 + index) (sidebar_width - 2) 1 action;
             line (sidebar_width - 2) a
               (" "
               ^ Text_layout.ellipsize (sidebar_width - 3) (clean ~newlines:false title)))
           entries
        @
        if window.cue = "" then []
        else [ line (sidebar_width - 2) (emphasis accent) window.cue ])
    in
    let repository_y = body_y + 1 + List.length window.pinned in
    if window.repositories.items <> [] then
      sidebar :=
        Some
          ( {
              x = 1;
              y = repository_y;
              w = sidebar_width - 2;
              h = List.length window.repositories.items;
            },
            window.repositories.offset );
    paint 0 body_y
      (border sidebar_width body_h ~title:"Factory" ~color:accent ~focused:false content));
  Pane_layout.hide t.pane_layout;
  (if body_h > 0 then
     if t.zoom && t.activity_expanded then
       activity { x = 0; y = body_y; w = cols; h = body_h }
     else if t.zoom then details { x = 0; y = body_y; w = cols; h = body_h }
     else
       match
         Pane_layout.choose ~preferences:t.pane_layout ~width:main_width ~height:body_h
           ~detail_focused:(t.focus <> Board) ()
       with
       | Pane_layout.Board ->
           board { x = sidebar_width; y = body_y; w = main_width; h = body_h }
       | Pane_layout.Detail ->
           details { x = sidebar_width; y = body_y; w = main_width; h = body_h }
       | Pane_layout.Side_by_side left ->
           board { x = sidebar_width; y = body_y; w = left; h = body_h };
           details
             { x = sidebar_width + left; y = body_y; w = main_width - left; h = body_h }
       | Pane_layout.Stacked top ->
           board { x = sidebar_width; y = body_y; w = main_width; h = top };
           details
             { x = sidebar_width; y = body_y + top; w = main_width; h = body_h - top });
  if
    !detail_visible && t.commands = None && t.model_target = None && (not t.help)
    && t.review = None && t.workspace_form = None
  then Task_updates.clear t.task_updates t.selected;
  let pending_keys =
    (if t.count = 0 then "" else string_of_int t.count)
    ^ match t.prefix with No_prefix -> "" | Go -> "g" | Window -> "Ctrl-W "
  in
  let input_text =
    match t.input with
    | Normal ->
        (if draft t = "" then " "
         else if
           Option.fold ~none:false ~some:(fun (task : task) -> task.state = Done) task
         then " Draft retained / read-only | "
         else " Draft saved. i to edit | ")
        ^ (if pending_keys = "" then "" else "[" ^ pending_keys ^ "] ")
        ^ t.status
    | Chat_search ->
        Input_line.render ~width:cols ~label:" Chat search: "
          ~hint:" [Enter finish / Esc close]" t.editor
    | Search ->
        Input_line.render ~width:cols ~label:" Search: "
          ~hint:"  [Enter finish / Esc close]" t.editor
    | Compose when !composer_editor_visible ->
        " Reply (queued): editing above · Enter sends / Esc keeps draft"
    | Compose ->
        Input_line.render ~width:cols ~label:" Reply (queued): "
          ~hint:"  [Enter send / Esc keep draft]" t.editor
    | Edit_model ->
        Input_line.render ~width:cols ~label:" Model (next run): "
          ~hint:" [Enter apply / Esc cancel]" t.editor
    | New_task ->
        Input_line.render ~width:cols ~label:" New task: "
          ~hint:"  [Enter create / Esc cancel]" t.editor
  in
  (* Tiny terminals retain the execution header instead of overwriting it with controls. *)
  if rows >= 4 then
    paint 0 (rows - 3)
      (line cols (attr (if t.input = Normal then muted else accent)) input_text);
  let x = ref 0 in
  let button title on_hit =
    let w = String.length title + 2 in
    if !x + w <= cols then (
      paint !x (rows - 2) (Hotkey_bar.action title);
      on_hit { x = !x; y = rows - 2; w; h = 1 };
      x := !x + w)
  in
  if rows >= 4 then
    if t.input = Normal then
      Action_bar.items
        ~board:(t.focus = Board && not t.zoom)
        ~archive:t.archive ~task ~live:(t.live_config <> None) ~replay:t.external_events
        ~fake:t.fake_harness ~storage:(t.database_path <> None) ~expanded:t.zoom
      |> List.iter (fun (title, action) ->
          button title (fun r -> hit r.x r.y r.w r.h action))
    else
      Input_controls.items t.input
      |> List.iter (fun (item : Input_controls.item) ->
          button item.label (fun rect ->
              input_controls :=
                { rect; input = t.input; action = item.action } :: !input_controls));
  if rows >= 4 then
    paint 0 (rows - 1)
      (Hotkey_bar.hints ~width:cols
         (match t.input_limit with
         | Some limit when t.input <> Normal ->
             Printf.sprintf
               " Edit not applied / limit %s · delete text or paste a smaller value"
               (if limit = 256 then "256 bytes" else "64 KiB")
         | _ when t.input <> Normal && t.input_error <> None ->
             " " ^ Option.get t.input_error
         | _ ->
             Shortcut_guidance.text ~width:cols ~input:t.input ~focus:t.focus
               ~expanded:t.zoom
               ~searching:(Chat_search.query t.chat_search <> "")
               ~prefix:t.prefix));
  if t.help then (
    let w = min 86 cols and h = min 31 rows in
    let x = (cols - w) / 2 and y = (rows - h) / 2 in
    let help_rows = Menu_content.help ~mode in
    let settings_rows =
      Menu_content.settings ~mode ~database:t.database_path ~task
        ~layout:(Pane_layout.defaults t.pane_layout)
    in
    let menu_rows = if t.menu_tab = Help_tab then help_rows else settings_rows in
    let menu_rows =
      List.concat_map
        (fun row -> if row = "" then [ "" ] else wrap_title (max 1 (w - 4)) row)
        menu_rows
    in
    let window = Menu_window.make ~height:h ~scroll:t.menu_scroll menu_rows in
    t.menu_scroll <- window.scroll;
    t.menu_page_rows <- max 1 window.capacity;
    if w > 2 && window.capacity > 0 then
      modal_scroll := Some { x = x + 1; y = y + 3; w = w - 2; h = window.capacity };
    let tab title tab =
      line 18 (if t.menu_tab = tab then emphasis accent else attr muted) title
    in
    let tabs = I.(tab " Help " Help_tab <|> tab " Settings " Settings_tab) in
    let content =
      I.vcat
        [
          tabs;
          line (max 0 (w - 4)) (attr muted) "";
          fit
            (max 0 (w - 4))
            window.capacity
            (I.vcat (List.map (line (max 0 (w - 4)) (attr text)) window.rows));
          line (max 0 (w - 4)) (emphasis accent) (Menu_window.position window);
        ]
      |> I.hpad 1 1
    in
    paint x y (border w h ~title:"Help / Settings" ~color:accent ~focused:true content);
    hits := [];
    input_controls := [];
    hit (x + 1) (y + 1) (min 18 (w - 2)) 1 (Menu_tab Help_tab);
    if w > 20 then hit (x + 19) (y + 1) (min 18 (w - 20)) 1 (Menu_tab Settings_tab));
  (match t.workspace_form with
  | None -> ()
  | Some form ->
      modal_scroll := None;
      let width = min 92 cols and height = min 26 rows in
      let x = (cols - width) / 2 and y = (rows - height) / 2 in
      let dialog =
        Workspace_dialog.render form
          ~busy:(t.creation_job <> None || t.creation_request <> None)
          ~status:(Workspace_form.status form) ~width ~height
      in
      paint x y dialog.image;
      hits := [];
      input_controls := [];
      List.iter
        (fun (item : Workspace_dialog.hit) ->
          let action =
            match item.action with
            | Workspace_dialog.Field field -> Workspace_field field
            | Workspace_dialog.Create -> Send_workspace
            | Workspace_dialog.Cancel -> Cancel_workspace
            | Workspace_dialog.Models -> Open_models
            | Workspace_dialog.Projects -> Open_projects
            | Workspace_dialog.Greenfield -> Toggle_greenfield
          in
          hit (x + item.x) (y + item.y) item.width 1 action)
        dialog.hits);
  (match t.review with
  | None -> ()
  | Some review ->
      let view = Review_view.render review ~width:cols ~height:(max 1 (rows - 1)) in
      modal_scroll :=
        Option.map
          (fun (region : Review_view.scroll_region) ->
            { x = region.x; y = region.y + 1; w = region.width; h = region.height })
          view.scroll_region;
      paint 0 1 view.image;
      hits := [];
      input_controls := [];
      List.iter
        (fun (item : Review_view.hit) ->
          let action =
            match item.action with
            | Review_view.Refresh -> Refresh_review
            | Review_view.Edit_executable -> Edit_review_executable
            | Review_view.Close -> Close_review
            | Review_view.Next_file -> Next_review_file
            | Review_view.Previous_file -> Previous_review_file
          in
          hit item.x (item.y + 1) item.width 1 action)
        view.hits);
  if t.model_target <> None then (
    let w = min 96 cols and h = min 28 rows in
    let x = (cols - w) / 2 and y = (rows - h) / 2 in
    let view = Model_picker_view.make t.model_picker ~width:w ~height:h in
    let content =
      I.vcat (List.map (line (max 0 (w - 4)) (attr text)) view.rows) |> I.hpad 1 1
    in
    let title =
      match t.model_target with
      | Some (Workspace_model _) -> "Gateway models / workspace form"
      | _ -> "Gateway models / next run"
    in
    paint x y (border w h ~title ~footer:view.footer ~color:accent ~focused:true content);
    hits := [];
    input_controls := [];
    modal_scroll := Some { x; y; w; h };
    List.iter
      (fun (item : Model_picker_view.hit) ->
        hit (x + item.x) (y + item.y) item.width 1
          (match item.choice with
          | Fetch -> Refresh_models
          | Close -> Close_models
          | Model id -> Choose_model id))
      view.hits);
  (match t.project_picker with
  | None -> ()
  | Some picker ->
      let w = min 96 cols and h = min 28 rows in
      let x = (cols - w) / 2 and y = (rows - h) / 2 in
      let inner = max 0 (w - 4) and capacity = max 0 ((h - 7) / 2) in
      Project_picker.capacity picker capacity;
      let projects = Project_picker.visible picker in
      let index = Project_picker.index picker in
      let offset = max 0 (index - capacity + 1) in
      let displayed =
        List.filteri (fun i _ -> i >= offset && i < offset + capacity) projects
      in
      let entries =
        if projects = [] then
          [ "No registered project matches. Add [projects.NAME] to TOML." ]
        else
          List.concat
            (List.mapi
               (fun i (project : Project.t) ->
                 [
                   (if i + offset = index then "> " else "  ")
                   ^ project.name ^ " / " ^ project.description;
                   "  " ^ project.source;
                 ])
               displayed)
      in
      let content =
        I.vcat
          (List.map
             (line inner (attr text))
             ([
                "Select a registered project; no filesystem scan or agent starts.";
                "Filter: " ^ Project_picker.query picker;
                "";
              ]
             @ entries))
        |> I.hpad 1 1
      in
      let footer = if w >= 18 && h >= 2 then "[Close / Esc]" else "" in
      paint x y
        (border w h ~title:"Registered projects / task workspace" ~footer ~color:accent
           ~focused:true content);
      hits := [];
      input_controls := [];
      modal_scroll := Some { x; y; w; h };
      if w >= 18 && h >= 2 then hit (x + 3) (y + h - 1) 13 1 Close_projects;
      List.iteri
        (fun i (project : Project.t) ->
          if capacity > 0 && w >= 5 then
            hit (x + 1) (y + 4 + (i * 2)) (w - 2) 2 (Choose_project project.name))
        displayed);
  (match t.commands with
  | None -> ()
  | Some commands ->
      Controller.refresh_commands t;
      let w = min 86 cols and h = min 25 rows in
      let x = (cols - w) / 2 and y = (rows - h) / 2 in
      let inner = max 1 (w - 4) in
      let capacity = max 0 ((h - 5) / 2) in
      let entries = Command_palette.visible commands in
      let index = Command_palette.index commands in
      let offset = max 0 (index - capacity + 1) in
      let shown =
        List.filteri (fun i _ -> i >= offset && i < offset + capacity) entries
      in
      let lines =
        if entries = [] then [ line inner (attr muted) "No matching commands." ]
        else
          List.concat
            (List.mapi
               (fun i (entry : Command_palette.entry) ->
                 let selected = i + offset = index in
                 let a = if selected then emphasis accent else attr text in
                 [
                   line inner a
                     ((if selected then "> " else "  ")
                     ^ entry.title
                     ^ if entry.shortcut = "" then "" else "  [" ^ entry.shortcut ^ "]");
                   line inner (attr muted) ("  " ^ Option.value ~default:"" entry.disabled);
                 ])
               shown)
      in
      let search =
        Input_line.render ~width:inner ~label:"Find: " ~hint:""
          (Command_palette.editor commands)
      in
      let content =
        I.vcat
          ([
             line inner (attr muted) "Enter selects · arrows move · Esc cancels";
             line inner (attr text) search;
             line inner (attr muted) "";
           ]
          @ lines)
        |> I.hpad 1 1
      in
      paint x y
        (border ~section:true w h ~title:"Commands / Ctrl-P"
           ~footer:"Esc cancels / draft stays saved" ~color:accent ~focused:true content);
      hits := [];
      input_controls := [];
      sidebar := None;
      column_regions := [];
      panes := [];
      scroll_panes := [];
      modal_scroll := Some { x; y; w; h };
      List.iteri
        (fun i (entry : Command_palette.entry) ->
          if entry.disabled = None && w > 4 then
            hit (x + 1) (y + 4 + (i * 2)) (w - 2) 1 (Choose_command entry.command))
        shown;
      if w >= 18 && h >= 2 then hit (x + 2) (y + h - 1) 12 1 Close_commands;
      if rows >= 4 then (
        paint 0 (rows - 2) (block cols 1 (attr muted));
        paint 0 (rows - 1) (block cols 1 (attr muted));
        paint 0 (rows - 2)
          (line cols (attr accent) " COMMANDS / Escape cancels and restores your mode");
        paint 0 (rows - 1)
          (line cols (attr muted)
             " Type to find a command · Enter selects · no command runs on open")));
  (match t.deletion with
  | None -> ()
  | Some dialog ->
      let w = min 86 cols in
      let inner = max 1 (w - 4) in
      let lines = List.concat_map (wrap_title inner) (Task_deletion.rows dialog) in
      let h = min rows (List.length lines + 2) in
      let x = (cols - w) / 2 and y = (rows - h) / 2 in
      let content = I.vcat (List.map (line inner (attr text)) lines) |> I.hpad 1 1 in
      paint x y
        (border ~section:true w h ~title:"Delete task / permanent"
           ~color:(state_color Needs_you) ~focused:true content);
      if rows >= 4 then (
        paint 0 (rows - 2) (block cols 1 (attr muted));
        paint 0 (rows - 1) (block cols 1 (attr muted));
        paint 0 (rows - 2) (line cols (attr muted) " Delete task / Esc cancels");
        paint 0 (rows - 1)
          (line cols
             (attr (state_color Needs_you))
             " y: delete task · n/Esc: cancel · workspace files stay intact"));
      hits := [];
      input_controls := [];
      sidebar := None;
      column_regions := [];
      panes := [];
      scroll_panes := [];
      modal_scroll := Some { x; y; w; h };
      if w >= 18 && h >= 2 then (
        paint (x + 2) (y + h - 1) (Hotkey_bar.action "[Cancel / Esc]");
        hit (x + 2) (y + h - 1) 14 1 Cancel_delete));
  {
    image = fit cols rows !canvas;
    hits = !hits;
    input_controls = !input_controls;
    sidebar = !sidebar;
    columns = !column_regions;
    panes = !panes;
    scroll_panes = !scroll_panes;
    modal_scroll = !modal_scroll;
  }

let mouse (t : Controller.t) frame ~now = function
  | `Press `Left, (x, y), _ ->
      if t.commands <> None then
        match hit_at frame x y with
        | Some ((Choose_command _ | Close_commands) as action) -> act t action
        | _ -> ()
      else if t.deletion <> None then (
        if hit_at frame x y = Some Cancel_delete then act t Cancel_delete)
      else if t.input = Normal then (
        reset_keys t;
        match hit_at frame x y with
        | Some action when t.project_picker <> None -> (
            match action with
            | Choose_project _ | Close_projects -> act t action
            | _ -> ())
        | Some action when t.model_target <> None -> (
            match action with
            | Refresh_models | Close_models | Choose_model _ -> act t action
            | _ -> ())
        | Some (Select id) ->
            let double =
              match t.last_click with
              | Some (previous, time) -> previous = id && now -. time < 0.4
              | None -> false
            in
            act t (Select id);
            t.last_click <- Some (id, now);
            if double then (
              t.last_click <- None;
              act t Open_conversation)
        | Some action ->
            t.last_click <- None;
            act t action
        | None -> t.last_click <- None)
      else if
        t.input = Compose && (not t.help) && t.review = None && t.workspace_form = None
        && t.model_target = None
      then
        match hit_at frame x y with
        | Some
            ((Select _ | Focus _ | Back | Session_board | Archive_view | Toggle_archive)
             as action) ->
            t.input <- Normal;
            act t action
        | _ ->
            List.find_opt
              (fun (hit : input_hit) ->
                let r = hit.rect in
                hit.input = t.input && x >= r.x
                && x < r.x + r.w
                && y >= r.y
                && y < r.y + r.h)
              frame.input_controls
            |> Option.iter (fun (hit : input_hit) ->
                Input_controls.key ~input:t.input hit.action |> Option.iter (key t))
      else if (not t.help) && t.review = None && t.workspace_form = None then
        List.find_opt
          (fun (hit : input_hit) ->
            let r = hit.rect in
            hit.input = t.input && x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h)
          frame.input_controls
        |> Option.iter (fun (hit : input_hit) ->
            t.last_click <- None;
            Input_controls.key ~input:t.input hit.action |> Option.iter (key t))
  | `Press (`Scroll direction), (x, y), mods ->
      let over_modal_content =
        match frame.modal_scroll with
        | Some r -> x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
        | None -> false
      in
      if t.commands <> None then (
        if over_modal_content then
          Command_palette.move (Option.get t.commands) (if direction = `Up then -3 else 3))
      else if t.deletion <> None then ()
      else if t.project_picker <> None then (
        if over_modal_content then
          Project_picker.move (Option.get t.project_picker)
            (if direction = `Up then -3 else 3))
      else if t.model_target <> None then (
        if over_modal_content then
          Model_picker.move t.model_picker (if direction = `Up then -3 else 3))
      else if t.workspace_form <> None then ()
      else if t.review <> None then (
        let review = Option.get t.review in
        if over_modal_content && not (Review.editing review) then
          if List.mem `Ctrl mods then
            Review.set_horizontal review
              (Review.horizontal review + if direction = `Up then -4 else 4)
          else
            Review.set_scroll review
              (Review.scroll review + if direction = `Up then -3 else 3))
      else if t.help then (
        if over_modal_content then
          t.menu_scroll <-
            max 0 (min 10000 (t.menu_scroll + if direction = `Up then -3 else 3)))
      else if hit_at frame x y = Some Follow_chat then ()
      else if t.input = Normal && t.workspace_form = None then (
        reset_keys t;
        let delta = if direction = `Up then -1 else 1 in
        let sidebar_offset =
          match frame.sidebar with
          | Some (r, offset) when x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
            ->
              Some offset
          | _ -> None
        in
        let column =
          List.find_opt
            (fun (r, _, _, _) ->
              x > r.x && x < r.x + r.w - 1 && y > r.y && y < r.y + r.h - 1)
            frame.columns
        in
        if column <> None then (
          let _, state, offset, maximum = Option.get column in
          act t (Focus Board);
          Column_scroll.set t.column_scroll state (min maximum (max 0 (offset + delta))))
        else if sidebar_offset <> None then
          t.sidebar_scroll <- Some (max 0 (Option.get sidebar_offset + (delta * 3)))
        else
          match
            List.find_opt
              (fun (r, _) -> x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h)
              frame.scroll_panes
          with
          | Some (_, Board) ->
              act t (Focus Board);
              t.board_scroll <- max 0 (t.board_scroll + delta)
          | Some (_, focus) ->
              act t (Focus focus);
              t.scroll <-
                max 0 (t.scroll + ((if focus = Activity then delta else -delta) * 3))
          | None -> ())
  | _ -> ()
