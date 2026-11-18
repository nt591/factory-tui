open Notty
open Model
open Controller

type rect = { x : int; y : int; w : int; h : int }
type hit = { rect : rect; action : action }

type frame = {
  image : image;
  hits : hit list;
  sidebar : (rect * int) option;
  columns : (rect * Model.state * int * int) list;
  panes : (rect * Controller.focus) list;
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

let border ?(footer = "") cols rows ~title ~color ~focused content =
  if cols < 2 || rows < 2 then fit cols rows content
  else
    let a = if focused then emphasis color else attr muted in
    let horizontal = String.concat "" (List.init (cols - 2) (fun _ -> "─")) in
    let top =
      I.(
        glyph a "╭"
        <|> (glyph a ("─ " ^ clean ~newlines:false title ^ " " ^ horizontal)
            |> hsnap ~align:`Left (cols - 2))
        <|> glyph a "╮")
    in
    let bottom =
      if footer = "" then glyph a ("╰" ^ horizontal ^ "╯")
      else
        I.(
          glyph a "╰"
          <|> (glyph a ("─ " ^ clean ~newlines:false footer ^ " " ^ horizontal)
              |> hsnap ~align:`Left (cols - 2))
          <|> glyph a "╯")
    in
    let middle =
      I.(
        uchar a (Uchar.of_int 0x2502) 1 (rows - 2)
        <|> (fit (cols - 2) (rows - 2) content </> block (cols - 2) (rows - 2) (attr text))
        <|> uchar a (Uchar.of_int 0x2502) 1 (rows - 2))
    in
    I.(top <-> middle <-> bottom)

let hit_at frame x y =
  List.find_opt
    (fun { rect; _ } ->
      x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h)
    frame.hits
  |> Option.map (fun hit -> hit.action)

let render t ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let canvas = ref (block cols rows A.(bg background)) and hits = ref [] in
  let paint x y image = canvas := I.(pad ~l:x ~t:y image </> !canvas) in
  let hit x y w h action =
    let w = min w (cols - x) and h = min h (rows - y) in
    if x >= 0 && y >= 0 && w > 0 && h > 0 then
      hits := { rect = { x; y; w; h }; action } :: !hits
  in
  let sidebar = ref None and column_regions = ref [] and panes = ref [] in
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
  let states = if t.archive then [ Done ] else columns in
  let meter_width = max 1 (main_width / List.length states) in
  List.iteri
    (fun i state ->
      let count =
        List.length (List.filter (fun (task : task) -> task.state = state) board_tasks)
      in
      let body = Printf.sprintf " %02d  %s" count (label state) in
      paint
        (sidebar_width + (i * meter_width))
        1
        (line meter_width (emphasis (state_color state)) body))
    states;
  let query = if t.query = "" then " / search tasks" else " / " ^ t.query in
  let summary =
    Printf.sprintf " %s  |  %d tasks%s  |%s"
      (if t.archive then "Archive"
       else match t.repository with None -> "Session board" | Some repo -> repo)
      (List.length board_tasks)
      (if t.archive then " accepted" else "")
      query
  in
  paint sidebar_width 2 (line main_width (attr muted) summary);
  hit sidebar_width 2 (min 19 main_width) 1 Toggle_archive;
  hit (max 0 (cols - 24)) 2 24 1 Begin_search;
  let body_y = 3 and body_h = max 0 (rows - 6) in
  let task = selected t in
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
      (border r.w chat_height ~title ~color:accent ~focused:(t.focus = Conversation)
         (if not searching then content
          else
            let position, count = Chat_search.position t.chat_search in
            let description =
              Printf.sprintf " /chat %s%s · %d/%d messages · n/N matches"
                (Chat_search.query t.chat_search)
                (if t.input = Chat_search then "▏" else "")
                position count
            in
            I.(line (r.w - 2) (emphasis accent) description <-> content)));
    panes := ({ r with h = chat_height }, Conversation) :: !panes;
    hit r.x r.y r.w chat_height (Focus Conversation);
    if composer_height > 0 then (
      let task = Option.get task in
      let editing = t.input = Compose in
      let prompt =
        if task.state = Done then "Accepted task / chat history is read-only"
        else if draft t = "" then if editing then "▏" else "Write a reply…  i to compose"
        else if editing then
          let value = Text_edit.text t.editor and cursor = Text_edit.cursor t.editor in
          String.sub value 0 cursor ^ "▏"
          ^ String.sub value cursor (String.length value - cursor)
        else draft t
      in
      let prompt = (if editing then "> " else "  ") ^ prompt in
      let instructions = Composer_guidance.text ~width:inner ~mode ~editing task in
      let prompt_rows = wrap inner prompt in
      let capacity = composer_height - 3 in
      let cursor_row =
        if not editing then List.length prompt_rows - 1
        else
          let before =
            String.sub (Text_edit.text t.editor) 0 (Text_edit.cursor t.editor)
          in
          List.length (wrap inner ("> " ^ before ^ "▏")) - 1
      in
      let offset = max 0 (cursor_row - capacity + 1) in
      let visible_rows =
        List.filteri (fun i _ -> i >= offset && i < offset + capacity) prompt_rows
      in
      let composer =
        I.vcat
          ( List.map (line inner (attr (if editing then text else muted))) visible_rows
          |> fun images ->
            [ fit inner capacity (I.vcat images); line inner (attr muted) instructions ]
          )
        |> I.hpad 1 1
      in
      paint r.x (r.y + chat_height)
        (border r.w composer_height ~title:"Reply / next turn" ~color:accent
           ~focused:editing composer);
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
      (border ~footer r.w r.h
         ~title:
           ((match task with None -> "Task" | Some task -> task.id)
           ^ " / activity"
           ^
           if t.activity_expanded then " / expanded · e or Esc returns"
           else " / e expands")
         ~color:accent ~focused:(t.focus = Activity) content);
    panes := (r, Activity) :: !panes;
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
    if t.board_list then panes := (r, Board) :: !panes;
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
        (border r.w r.h ~title:"Session board" ~color:accent ~focused:(t.focus = Board)
           content);
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
              (Printf.sprintf " %s %-7s %-10s %s"
                 (if task.id = t.selected then "›" else " ")
                 task.id (label task.state) task.title))
          tasks
      in
      let title =
        if Board_window.cue window = "" then "Tasks / click to focus / e expand"
        else "Tasks / click · " ^ Board_window.cue window ^ " · e expand"
      in
      paint r.x r.y
        (border r.w r.h ~title ~color:accent ~focused:(t.focus = Board) (I.vcat rows)))
    else
      let col_w = r.w / 4 in
      List.iteri
        (fun column state ->
          let x = r.x + (column * col_w) in
          let w = if column = 3 then r.w - (column * col_w) else col_w in
          let items = List.filter (fun (task : task) -> task.state = state) tasks in
          let capacity = max 0 ((r.h - 2) / 7) in
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
                let pending =
                  List.length (List.filter (fun (m : message) -> m.queued) task.messages)
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
                        (if pending = 0 then
                           Printf.sprintf "%d messages" (List.length task.messages)
                         else
                           Printf.sprintf "%d msg / %d queued" (List.length task.messages)
                             pending);
                    ]
                  |> I.hpad 1 1
                in
                hit (x + 1) (r.y + 1 + (index * 7)) (w - 2) 6 (Select task.id);
                let title = task.id ^ if selected then " ◂" else "" in
                I.(
                  border (w - 2) 6 ~title ~color:(state_color state) ~focused:selected
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
            Printf.sprintf "%s %d%s" (label state) (List.length items)
              (if Board_window.cue window = "" then ""
               else " / " ^ Board_window.cue window)
          in
          paint x r.y
            (border w r.h ~title ~color:(state_color state)
               ~focused:
                 (t.focus = Board
                 && match task with Some task -> task.state = state | None -> false)
               content))
        columns
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
  (if body_h > 0 then
     if t.zoom && t.activity_expanded then
       activity { x = 0; y = body_y; w = cols; h = body_h }
     else if t.zoom then details { x = 0; y = body_y; w = cols; h = body_h }
     else
       match
         Pane_layout.choose ~width:main_width ~height:body_h
           ~detail_focused:(t.focus <> Board)
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
  let pending_keys =
    (if t.count = 0 then "" else string_of_int t.count)
    ^ match t.prefix with No_prefix -> "" | Go -> "g" | Window -> "Ctrl-W "
  in
  let input_text =
    match t.input with
    | Normal ->
        (if draft t <> "" then " Draft saved. i to edit | " else " ")
        ^ (if pending_keys = "" then "" else "[" ^ pending_keys ^ "] ")
        ^ t.status
    | Chat_search ->
        Input_line.render ~width:cols ~label:" Chat search: "
          ~hint:" [Enter finish / Esc close]" t.editor
    | Search ->
        Input_line.render ~width:cols ~label:" Search: "
          ~hint:"  [Enter finish / Esc close]" t.editor
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
  let buttons =
    Action_bar.items ~task ~live:(t.live_config <> None) ~replay:t.external_events
      ~fake:t.fake_harness ~storage:(t.database_path <> None) ~expanded:t.zoom
  in
  let x = ref 0 in
  if rows >= 4 then
    List.iter
      (fun (title, action) ->
        let w = String.length title + 2 in
        if !x + w <= cols then (
          paint !x (rows - 2) (line w (emphasis accent) (" " ^ title ^ " "));
          hit !x (rows - 2) w 1 action;
          x := !x + w))
      buttons;
  if rows >= 4 then
    paint 0 (rows - 1)
      (line cols
         A.(fg muted ++ bg background)
         " hjkl: move · gg/G: first/last · Ctrl-W hjkl: pane · Ctrl-U/D: half-page · \
          Ctrl-B/F: page · e: zoom · Esc: back");
  if t.help then (
    let w = min 86 cols and h = min 31 rows in
    let x = (cols - w) / 2 and y = (rows - h) / 2 in
    let help_rows = Menu_content.help ~mode in
    let settings_rows = Menu_content.settings ~mode ~database:t.database_path ~task in
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
      List.iter
        (fun (item : Workspace_dialog.hit) ->
          let action =
            match item.action with
            | Workspace_dialog.Field field -> Workspace_field field
            | Workspace_dialog.Create -> Submit_workspace
            | Workspace_dialog.Cancel -> Cancel_workspace
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
  (match t.live_confirmation with
  | None -> ()
  | Some id ->
      modal_scroll := None;
      let width = min 88 cols in
      let task = List.find_opt (fun (task : task) -> task.id = id) t.tasks in
      let policy =
        match t.live_config with
        | None -> Model.Read_only
        | Some config -> Live_runner.policy config
      in
      let height = min rows (Live_confirmation.required_height ~policy task ~width) in
      let x = (cols - width) / 2 and y = (rows - height) / 2 in
      let view = Live_confirmation.render ~policy task ~width ~height in
      t.confirmation_readable <- view.readable;
      paint x y view.image;
      hits := [];
      List.iter
        (fun (item : Live_confirmation.hit) ->
          hit (x + item.x) (y + item.y) item.width 1
            (match item.action with
            | Live_confirmation.Run -> Confirm_live
            | Live_confirmation.Cancel -> Cancel_live))
        view.hits);

  {
    image = fit cols rows !canvas;
    hits = !hits;
    sidebar = !sidebar;
    columns = !column_regions;
    panes = !panes;
    modal_scroll = !modal_scroll;
  }

let mouse t frame ~now = function
  | `Press `Left, (x, y), _ ->
      if t.input = Normal then (
        reset_keys t;
        match hit_at frame x y with
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
              act t Zoom)
        | Some action ->
            t.last_click <- None;
            act t action
        | None -> t.last_click <- None)
  | `Press (`Scroll direction), (x, y), mods ->
      let over_modal_content =
        match frame.modal_scroll with
        | Some r -> x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
        | None -> false
      in
      if t.live_confirmation <> None || t.workspace_form <> None then ()
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
            (fun (r, _, _, _) -> x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h)
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
              frame.panes
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
