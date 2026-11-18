open Notty
open Model
open Controller

type rect = { x : int; y : int; w : int; h : int }
type hit = { rect : rect; action : action }
type frame = { image : image; hits : hit list }

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

let border cols rows ~title ~color ~focused content =
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
    let bottom = glyph a ("╰" ^ horizontal ^ "╯") in
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
  let header =
    Printf.sprintf " FACTORY / terminal     %s  %s"
      (if t.live_config <> None then
         if
           Option.fold ~none:false
             ~some:(fun config -> Live_runner.policy config = Model.Workspace_write)
             t.live_config
         then "LIVE WRITE / CONFIRMED CALLS"
         else "LIVE ENABLED / CONFIRMED CALLS"
       else if t.fake_harness then "FAKE HARNESS / NO MODEL CALLS"
       else if t.external_events then "FIXTURE REPLAY"
       else "SIMULATION")
      (if t.paused then "[PAUSED]" else "[UPDATING]")
  in
  paint 0 0 (line cols A.(fg accent ++ bg background ++ st bold) header);
  let sidebar_width = if cols >= 145 && not t.zoom then 22 else 0 in
  let main_width = cols - sidebar_width in
  let states = if t.archive then [ Done ] else columns in
  let meter_width = max 1 (main_width / List.length states) in
  List.iteri
    (fun i state ->
      let count =
        List.length (List.filter (fun (task : task) -> task.state = state) t.tasks)
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
      (List.length (visible t))
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
    let title, rows =
      match task with
      | None ->
          ( "Conversation",
            List.map
              (fun line -> (muted, line, None, 0))
              (if t.live_config = None then [ "Select a task. Enter or e expands it." ]
               else
                 [
                   "A task's conversation will appear here.";
                   "Create a workspace task with W or n.";
                   "Messages and drafts are saved to your configured SQLite database.";
                 ]) )
      | Some task ->
          Chat_search.sync t.chat_search task.messages;
          let rows =
            List.concat_map
              (fun (m : message) ->
                let body = wrap inner m.text in
                ( (if m.queued then state_color Needs_you else accent),
                  (m.author
                  ^
                  if m.queued then " / queued"
                  else if m.author = "You" then " / sent"
                  else ""),
                  Some m.id,
                  0 )
                :: (List.mapi (fun index row -> (text, row, Some m.id, index + 1)) body
                   @ [ (muted, "", Some m.id, 1 + List.length body) ]))
              task.messages
          in
          (task.id ^ " / " ^ label task.state ^ " / conversation", rows)
    in
    let searching = t.input = Chat_search || Chat_search.query t.chat_search <> "" in
    let available = max 0 (chat_height - 2 - if searching then 1 else 0) in
    if t.focus = Conversation then t.page_rows <- max 1 available;
    let view =
      Chat_viewport.update t.chat_viewport ~task_id:t.selected
        ~rows:
          (List.map (fun (_, _, id, index) -> (Option.value ~default:"" id, index)) rows)
        ~height:available
        ~distance:
          (if t.focus = Activity then Chat_viewport.distance t.chat_viewport else t.scroll)
        ~seek:(Chat_search.seek t.chat_search)
    in
    if available > 0 && t.focus <> Activity then t.scroll <- view.distance;
    let title =
      title ^ if view.following then "" else " / reading history · End follows"
    in
    let rows = Chat_viewport.visible_rows view ~height:available rows in
    let content =
      I.vcat
        (List.map
           (fun (color, text, id, _) ->
             let attribute =
               match id with
               | Some id when Chat_search.current t.chat_search = Some id ->
                   A.(attr color ++ bg (color_rgb 38 57 72) ++ st bold)
               | Some id when Chat_search.matches t.chat_search id ->
                   A.(attr color ++ st underline)
               | _ -> attr color
             in
             I.hpad 1 1 (line inner attribute text))
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
      let selection = harness_label task.harness ^ " / " ^ task.model in
      let instructions =
        if task.state = Done then "Accepted / read-only"
        else
          selection ^ "  ·  "
          ^
          if editing then "Enter queues / Ctrl-L newline / Esc keeps draft"
          else "m model / H harness"
      in
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
    let rows =
      Activity_content.lines ~expanded:t.tools_expanded ~raw:t.raw_tools
        ~waiting:(List.mem t.selected t.live_waiting_tasks)
        task
      |> List.concat_map (wrap inner)
    in
    if t.focus = Activity then (
      t.page_rows <- max 1 (r.h - 2);
      t.scroll <- min t.scroll (max 0 (List.length rows - max 0 (r.h - 2))));
    let offset =
      if t.focus = Activity then min t.scroll (max 0 (List.length rows - max 0 (r.h - 2)))
      else 0
    in
    let content =
      I.vcat
        (List.filteri (fun i _ -> i >= offset) rows
        |> List.map (fun row -> I.hpad 1 1 (line inner (attr muted) row)))
    in
    paint r.x r.y
      (border r.w r.h
         ~title:
           ((match task with None -> "Task" | Some task -> task.id)
           ^ " / activity"
           ^
           if t.activity_expanded then " / expanded · e or Esc returns"
           else " / e expands")
         ~color:accent ~focused:(t.focus = Activity) content);
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
      let offset =
        if t.board_scroll > 0 then
          min t.board_scroll (max 0 (List.length tasks - capacity))
        else max 0 (selected_index - capacity + 1)
      in
      let tasks = List.filteri (fun i _ -> i >= offset && i < offset + capacity) tasks in
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
      paint r.x r.y
        (border r.w r.h ~title:"Tasks / click to focus / e expand" ~color:accent
           ~focused:(t.focus = Board) (I.vcat rows)))
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
          let offset =
            if t.board_scroll > 0 then
              min t.board_scroll (max 0 (List.length items - capacity))
            else max 0 (selected_index - capacity + 1)
          in
          let shown =
            List.filteri (fun i _ -> i >= offset && i < offset + capacity) items
          in
          let cards =
            List.mapi
              (fun index (task : task) ->
                let selected = task.id = t.selected in
                let a =
                  if selected then A.(fg text ++ bg (color_rgb 38 57 72)) else attr text
                in
                let title_rows =
                  wrap_title (max 1 (w - 8)) task.title |> List.filteri (fun i _ -> i < 2)
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
                      line (w - 6) (attr muted) task.repository;
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
            if shown = [] then line (w - 2) (attr muted) "  No tasks" else I.vcat cards
          in
          let title =
            Printf.sprintf "%s %d%s" (label state) (List.length items)
              (if List.length items > capacity then " / scroll" else "")
          in
          paint x r.y
            (border w r.h ~title ~color:(state_color state)
               ~focused:
                 (t.focus = Board
                 && match task with Some task -> task.state = state | None -> false)
               content))
        columns
  in
  (if sidebar_width > 0 then
     let entries =
       [
         ("Session board", Session_board);
         ("Archive", Archive_view);
         ((if t.live_config = None then "+ Demo task" else "+ New task"), Begin_new);
         ("+ Workspace task", Begin_workspace);
         ("? Help / settings", Help);
         ("", Help);
         ("REPOSITORIES", Help);
         ("All repositories", Repository None);
       ]
       @ List.map (fun repo -> (repo, Repository (Some repo))) (repositories t)
     in
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
              line (sidebar_width - 2) a (" " ^ title))
            entries)
     in
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
        " Chat search: "
        ^ Chat_search.query t.chat_search
        ^ "▏ [Enter finish / Esc close]"
    | Search -> " Search: " ^ t.query ^ "▏  [Enter finish / Esc close]"
    | Compose -> " Reply (queued): " ^ draft t ^ "▏  [Enter send / Esc keep draft]"
    | Edit_model -> " Model (next run): " ^ t.model_text ^ "▏ [Enter apply / Esc cancel]"
    | New_task -> " New task: " ^ t.new_title ^ "▏  [Enter create / Esc cancel]"
  in
  if rows >= 3 then
    paint 0 (rows - 3)
      (line cols (attr (if t.input = Normal then muted else accent)) input_text);
  let buttons =
    Action_bar.items ~task ~live:(t.live_config <> None) ~replay:t.external_events
      ~fake:t.fake_harness ~storage:(t.database_path <> None) ~expanded:t.zoom
  in
  let x = ref 0 in
  if rows >= 2 then
    List.iter
      (fun (title, action) ->
        let w = String.length title + 2 in
        if !x + w <= cols then (
          paint !x (rows - 2) (line w (emphasis accent) (" " ^ title ^ " "));
          hit !x (rows - 2) w 1 action;
          x := !x + w))
      buttons;
  if rows >= 1 then
    paint 0 (rows - 1)
      (line cols
         A.(fg muted ++ bg background)
         " hjkl: move · gg/G: first/last · Ctrl-W hjkl: pane · Ctrl-U/D: half-page · \
          Ctrl-B/F: page · e: zoom · Esc: back");
  if t.help then (
    let w = min 86 cols and h = min 31 rows in
    let x = (cols - w) / 2 and y = (rows - h) / 2 in
    let help_rows =
      [
        "FACTORY / terminal";
        "";
        "Click a card to inspect chat. Enter/e expands; Escape returns.";
        "Focus Activity and e expands tool output to full terminal width.";
        "hjkl/arrows navigate. Counts repeat movement (for example, 3j).";
        "gg / G: first / last card, or top / bottom of the focused pane.";
        "Ctrl-W then hjkl moves pane focus. Ctrl-W w cycles panes.";
        "Ctrl-U/D: half-page. Ctrl-B/F: full-page. Tab/Shift-Tab: cycle.";
        "Mouse wheel and Page Up/Down scroll. Home/End: first/last.";
        "i composes a reply. Enter queues; Ctrl-L/Alt-Enter adds a line.";
        "Arrows edit; Home/End move within a line; Escape keeps the draft.";
        "n creates a demo, or a workspace task in live mode. W: workspace.";
        "m edits next-run model. H cycles Codex / Claude.";
        "s starts a demo or asks for live confirmation; x stops; a accepts.";
        "b returns to all tasks. R cycles repositories. d opens Archive.";
        "v opens real workspace changes; r refreshes; Escape returns.";
        "Review: [/]: previous/next file; h/l: long lines; Page Up/Down: page.";
        "t expands tools; T toggles readable/raw payload. f pauses demo.";
        "/ searches focused board or chat. S searches chat from any pane.";
        "In chat search: n/N moves matches; Escape clears. Literal search.";
        "";
        "Cards move from events; selected chat stays attached to its task.";
        "Process exit alone never marks a task Ready.";
        "Acceptance does not merge, push, or delete a workspace.";
        "Startup starts no agent. Live mode and writes require explicit opt-in.";
        "Configured SQLite storage retains chats and drafts.";
        "";
        "Menu: Tab/h/l switches tabs; j/k scrolls; ? or Escape closes.";
      ]
    in
    let settings_rows =
      [
        "SESSION SETTINGS";
        "";
        ("Execution: "
        ^
        match t.live_config with
        | Some config ->
            "live Codex / " ^ Live_runner.policy_label config ^ " / confirmation required"
        | None ->
            if t.fake_harness then "local process fixtures"
            else if t.external_events then "fixture replay"
            else "simulated agents");
        "Setup never starts an agent. Live runs require confirmation.";
        "";
        "STORAGE";
        (match t.database_path with
        | None -> "In memory / data is discarded on exit."
        | Some path -> "SQLite / " ^ path);
        "Config: ~/.config/factory-tui/config.toml or --config PATH";
        {|[storage] database = "board.sqlite"|};
        "Database changes take effect on the next launch.";
        "Optional [workspace]: jj, source, parent, revision, model prefill W.";
        "Defaults never create workspaces or enable live execution.";
        "Stored conversations and tool output are sensitive.";
        "";
        "NEXT RUN / SELECTED TASK";
      ]
      @ (match task with
        | None -> [ "Select a task first." ]
        | Some task ->
            [
              task.id ^ " / " ^ task.title;
              ("Harness: " ^ harness_label task.harness
              ^ if t.live_config = None then " (simulated)" else " / live Codex only");
              "Model: " ^ task.model;
              (if task.state = Done then "Accepted task / settings are read-only"
               else "m edits model / H changes harness");
              "Past run settings do not change.";
            ])
      @ [ ""; "Menu: Tab/h/l switches tabs; j/k scrolls; ? or Escape closes." ]
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
      let width = min 92 cols and height = min 26 rows in
      let x = (cols - width) / 2 and y = (rows - height) / 2 in
      let dialog =
        Workspace_dialog.render form
          ~busy:(t.creation_job <> None || t.creation_request <> None)
          ~status:t.status ~width ~height
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
      let width = min 88 cols and height = min 13 rows in
      let x = (cols - width) / 2 and y = (rows - height) / 2 in
      let task = List.find_opt (fun (task : task) -> task.id = id) t.tasks in
      let view =
        Live_confirmation.render
          ~policy:
            (match t.live_config with
            | None -> Model.Read_only
            | Some config -> Live_runner.policy config)
          task ~width ~height
      in
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

  { image = fit cols rows !canvas; hits = !hits }

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
      if t.live_confirmation <> None then ()
      else if t.help then
        t.menu_scroll <-
          max 0 (min 10000 (t.menu_scroll + if direction = `Up then -3 else 3))
      else if t.review <> None then (
        let review = Option.get t.review in
        if not (Review.editing review) then
          if List.mem `Ctrl mods then
            Review.set_horizontal review
              (Review.horizontal review + if direction = `Up then -4 else 4)
          else
            Review.set_scroll review
              (Review.scroll review + if direction = `Up then -3 else 3))
      else if t.input = Normal && t.workspace_form = None then (
        reset_keys t;
        (match hit_at frame x y with
        | Some (Focus focus) -> t.focus <- focus
        | Some (Select _) -> t.focus <- Board
        | _ -> ());
        let delta = if direction = `Up then -1 else 1 in
        if t.focus = Board && not t.zoom then
          t.board_scroll <- max 0 (t.board_scroll + delta)
        else
          t.scroll <-
            max 0 (t.scroll + ((if t.focus = Activity then delta else -delta) * 3)))
  | _ -> ()
