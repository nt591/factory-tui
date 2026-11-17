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
  | Queued -> muted | Working -> accent | Needs_you -> color_rgb 239 185 99
  | Ready | Done -> color_rgb 147 203 154
let attr color = A.(fg color ++ bg panel)
let emphasis color = A.(attr color ++ st bold)
let line cols a text = I.(string a (clean ~newlines:false text) |> hsnap ~align:`Left cols)
let fit w h image = I.(image |> hsnap ~align:`Left (max 0 w) |> vsnap ~align:`Top (max 0 h))
let block cols rows a = I.char a ' ' (max 0 cols) (max 0 rows)
let glyph a s = I.string a s

let wrap cols text =
  let cols = max 1 cols in
  let current = Buffer.create cols and cells = ref 0 and rows = ref [] in
  let flush () = rows := Buffer.contents current :: !rows; Buffer.clear current; cells := 0 in
  Uutf.String.fold_utf_8 (fun () _ -> function
    | `Malformed _ -> ()
    | `Uchar u ->
        if Uchar.to_int u = 10 then flush ()
        else (
          let b = Buffer.create 4 in Uutf.Buffer.add_utf_8 b u;
          let s = Buffer.contents b in
          let size = I.width (I.string A.empty s) in
          if !cells + size > cols && !cells > 0 then flush ();
          Buffer.add_string current s; cells := !cells + size)) () (clean text);
  flush (); List.rev !rows

let wrap_title cols title =
  let words = String.split_on_char ' ' (clean ~newlines:false title) in
  let width text = I.width (I.string A.empty text) in
  let rec loop current rows = function
    | [] -> List.rev (if current = "" then rows else current :: rows)
    | word :: rest ->
        let combined = if current = "" then word else current ^ " " ^ word in
        if width combined <= cols then loop combined rows rest
        else if current <> "" then loop "" (current :: rows) (word :: rest)
        else (
          let parts = wrap cols word in
          match List.rev parts with
          | last :: previous -> loop last (previous @ rows) rest
          | [] -> loop "" rows rest) in
  loop "" [] words

let border cols rows ~title ~color ~focused content =
  if cols < 2 || rows < 2 then fit cols rows content
  else
    let a = if focused then emphasis color else attr muted in
    let horizontal = String.concat "" (List.init (cols - 2) (fun _ -> "─")) in
    let top = I.(glyph a "╭" <|>
      (glyph a ("─ " ^ clean ~newlines:false title ^ " " ^ horizontal) |> hsnap ~align:`Left (cols - 2)) <|> glyph a "╮") in
    let bottom = glyph a ("╰" ^ horizontal ^ "╯") in
    let middle = I.(uchar a (Uchar.of_int 0x2502) 1 (rows - 2) <|>
      (fit (cols - 2) (rows - 2) content </> block (cols - 2) (rows - 2) (attr text)) <|> uchar a (Uchar.of_int 0x2502) 1 (rows - 2)) in
    I.(top <-> middle <-> bottom)

let hit_at frame x y =
  List.find_opt (fun {rect; _} -> x >= rect.x && x < rect.x + rect.w &&
    y >= rect.y && y < rect.y + rect.h) frame.hits |> Option.map (fun hit -> hit.action)

let render t ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let canvas = ref (block cols rows A.(bg background)) and hits = ref [] in
  let paint x y image = canvas := I.(pad ~l:x ~t:y image </> !canvas) in
  let hit x y w h action =
    let w = min w (cols - x) and h = min h (rows - y) in
    if x >= 0 && y >= 0 && w > 0 && h > 0 then hits := {rect = {x; y; w; h}; action} :: !hits in
  let header = Printf.sprintf " FACTORY / terminal     %s  %s"
    (if t.external_events then "FIXTURE REPLAY" else "SIMULATION") (if t.paused then "[PAUSED]" else "[UPDATING]") in
  paint 0 0 (line cols A.(fg accent ++ bg background ++ st bold) header);
  let states = if t.archive then [Done] else columns in
  let meter_width = max 1 (cols / List.length states) in
  List.iteri (fun i state ->
    let count = List.length (List.filter (fun (task : task) -> task.state = state) t.tasks) in
    let body = Printf.sprintf " %02d  %s" count (label state) in
    paint (i * meter_width) 1 (line meter_width (emphasis (state_color state)) body)) states;
  let query = if t.query = "" then " / search tasks" else " / " ^ t.query in
  let summary = Printf.sprintf " %s  |  %d tasks%s  |%s"
    (if t.archive then "Archive" else "Session board") (List.length (visible t))
    (if t.archive then " accepted" else "") query in
  paint 0 2 (line cols (attr muted) summary);
  hit 0 2 (min 19 cols) 1 Toggle_archive;
  hit (max 0 (cols - 24)) 2 24 1 Begin_search;
  let body_y = 3 and body_h = max 0 (rows - 6) in
  let task = selected t in
  let conversation r =
    let inner = max 1 (r.w - 4) in
    let title, rows = match task with
      | None -> "Conversation", [muted, "Select a task. Enter or e expands it."]
      | Some task ->
        let rows = List.concat_map (fun (m : message) ->
          ((if m.queued then state_color Needs_you else accent),
           m.author ^ if m.queued then " / queued" else "") ::
          List.map (fun row -> text, row) (wrap inner m.text) @ [muted, ""]) task.messages in
        task.id ^ " / " ^ label task.state ^ " / conversation", rows in
    let available = max 0 (r.h - 2) in
    let offset = max 0 (List.length rows - available - t.scroll) in
    let rows = List.filteri (fun i _ -> i >= offset) rows in
    let content = I.vcat (List.map (fun (color, text) -> I.hpad 1 1 (line inner (attr color) text)) rows) in
    paint r.x r.y (border r.w r.h ~title ~color:accent ~focused:(t.focus = Conversation) content);
    hit r.x r.y r.w r.h (Focus Conversation) in
  let activity r =
    let inner = max 1 (r.w - 4) in
    let rows = match task with
      | None -> ["No task selected."]
      | Some task ->
          [task.title; "repo: " ^ task.repository;
           "run: " ^ (match task.active with None -> "idle" | Some run -> run.id);
           "updates: " ^ string_of_int task.revision; ""] @
          (if task.tools = [] then ["No tool activity yet."]
           else List.concat_map (fun (_, detail) -> wrap inner detail @ [""]) task.tools) in
    let offset = if t.focus = Activity then min t.scroll (max 0 (List.length rows - max 0 (r.h - 2))) else 0 in
    let content = I.vcat (List.filteri (fun i _ -> i >= offset) rows |> List.map (fun row ->
      I.hpad 1 1 (line inner (attr muted) row))) in
    paint r.x r.y (border r.w r.h ~title:"Task / activity" ~color:accent ~focused:(t.focus = Activity) content);
    hit r.x r.y r.w r.h (Focus Activity) in
  let details r =
    if r.w >= 70 then (
      let left = r.w * 2 / 3 in
      conversation {r with w = left}; activity {r with x = r.x + left; w = r.w - left})
    else if r.h >= 16 then (
      let top = r.h * 2 / 3 in
      conversation {r with h = top}; activity {r with y = r.y + top; h = r.h - top})
    else if t.focus = Activity then activity r else conversation r in
  let board r =
    let tasks = visible t in
    if r.w < 88 || t.archive then (
      let content_width = max 1 (r.w - 2) in
      let capacity = max 0 (r.h - 2) in
      let selected_index =
        let rec find i = function [] -> 0 | (task : task) :: _ when task.id = t.selected -> i | _ :: rest -> find (i + 1) rest in
        find 0 tasks in
      let offset = if t.board_scroll > 0 then min t.board_scroll (max 0 (List.length tasks - capacity))
        else max 0 (selected_index - capacity + 1) in
      let tasks = List.filteri (fun i _ -> i >= offset && i < offset + capacity) tasks in
      let rows = List.mapi (fun i (task : task) ->
        let a = if task.id = t.selected then A.(emphasis accent ++ bg (color_rgb 38 57 72)) else attr text in
        hit (r.x + 1) (r.y + 1 + i) content_width 1 (Select task.id);
        line content_width a (Printf.sprintf " %s %-7s %-10s %s"
          (if task.id = t.selected then "›" else " ") task.id (label task.state) task.title)) tasks in
      paint r.x r.y (border r.w r.h ~title:"Tasks / click to focus / e expand" ~color:accent ~focused:(t.focus = Board) (I.vcat rows)))
    else (
      let col_w = r.w / 4 in
      List.iteri (fun column state ->
        let x = r.x + column * col_w in
        let w = if column = 3 then r.w - column * col_w else col_w in
        let items = List.filter (fun (task : task) -> task.state = state) tasks in
        let capacity = max 0 ((r.h - 2) / 6) in
        let selected_index =
          let rec find i = function [] -> 0 | (task : task) :: _ when task.id = t.selected -> i | _ :: rest -> find (i + 1) rest in find 0 items in
        let offset = if t.board_scroll > 0 then min t.board_scroll (max 0 (List.length items - capacity))
          else max 0 (selected_index - capacity + 1) in
        let shown = List.filteri (fun i _ -> i >= offset && i < offset + capacity) items in
        let cards = List.mapi (fun index (task : task) ->
          let selected = task.id = t.selected in
          let a = if selected then A.(fg text ++ bg (color_rgb 38 57 72)) else attr text in
          let title_rows = wrap_title (max 1 (w - 6)) task.title |> List.filteri (fun i _ -> i < 2) in
          let title_image = I.vcat (List.map (fun title -> line (w - 4) a (" " ^ title)) title_rows) |> fit (w - 4) 2 in
          let card = I.vcat [
            line (w - 4) (emphasis (state_color state)) (" " ^ task.id ^ if selected then "  ◂ selected" else "");
            title_image;
            line (w - 4) (attr muted) (" " ^ task.repository);
            line (w - 4) (attr muted) (Printf.sprintf " %d messages · %d updates" (List.length task.messages) task.revision)] in
          hit (x + 1) (r.y + 1 + index * 6) (w - 2) 5 (Select task.id);
          I.(fit (w - 2) 5 (hpad 1 1 card) <-> block (w - 2) 1 (attr muted))) shown in
        let content = if shown = [] then line (w - 2) (attr muted) "  No tasks" else I.vcat cards in
        let title = Printf.sprintf "%s %d%s" (label state) (List.length items)
          (if List.length items > capacity then " / scroll" else "") in
        paint x r.y (border w r.h ~title ~color:(state_color state)
          ~focused:(t.focus = Board && match task with Some task -> task.state = state | None -> false) content)) columns) in
  if body_h > 0 then (
    if t.zoom then details {x = 0; y = body_y; w = cols; h = body_h}
    else if cols >= 145 then (
      let left = cols * 64 / 100 in
      board {x = 0; y = body_y; w = left; h = body_h};
      details {x = left; y = body_y; w = cols - left; h = body_h})
    else if body_h >= 17 then (
      let top = max 9 (body_h * 55 / 100) in
      board {x = 0; y = body_y; w = cols; h = top};
      details {x = 0; y = body_y + top; w = cols; h = body_h - top})
    else board {x = 0; y = body_y; w = cols; h = body_h});
  let input_text = match t.input with
    | Normal -> (if draft t <> "" then " Draft saved. i to edit | " else " ") ^ t.status
    | Search -> " Search: " ^ t.query ^ "▏  [Enter finish / Esc close]"
    | Compose -> " Reply (queued): " ^ draft t ^ "▏  [Enter send / Esc keep draft]"
    | New_task -> " New task: " ^ t.new_title ^ "▏  [Enter create / Esc cancel]" in
  if rows >= 3 then paint 0 (rows - 3) (line cols (attr (if t.input = Normal then muted else accent)) input_text);
  let buttons = ["? help", Help; "e expand", Zoom; "i reply", Begin_compose; "s start", Start;
    "x stop", Stop; "a accept", Accept; "n new", Begin_new; "d archive", Toggle_archive;
    "f pause", Toggle_pause; "q quit", Quit] in
  let x = ref 0 in
  if rows >= 2 then List.iter (fun (title, action) ->
    let w = String.length title + 2 in
    if !x + w <= cols then (
      paint !x (rows - 2) (line w (emphasis accent) (" " ^ title ^ " "));
      hit !x (rows - 2) w 1 action; x := !x + w)) buttons;
  if rows >= 1 then paint 0 (rows - 1) (line cols A.(fg muted ++ bg background)
    " Mouse: select / double-click expand · Tab: pane · hjkl/arrows: navigate · PgUp/PgDn: scroll · Esc: back");
  if t.help then (
    let w = min 82 cols and h = min 20 rows in
    let help_rows = ["FACTORY / terminal prototype"; "";
      "Click a task to select it. Double-click or Enter/e to expand.";
      "Tab cycles Board, Conversation, Activity. Focus is bordered.";
      "Arrow keys or hjkl navigate tasks and scroll the focused pane.";
      "Mouse wheel and Page Up/Down scroll. Home: top. End: follow.";
      "/ filters task title, ID, and repository. Escape clears search.";
      "i opens the reply composer. Enter queues a reply for the next run.";
      "n creates an in-memory task. s starts a simulated run.";
      "x interrupts a simulated run. a accepts a Ready task.";
      "d opens accepted tasks. f pauses/resumes demo events.";
      ""; "Cards move from validated events. Selection follows task identity.";
      "A process exit without completion never marks work Ready.";
      "Acceptance does not merge, push, or delete a workspace.";
      "No live agents, credentials, persistence, or workspace writes.";
      ""; "Press ? or Escape to close."] in
    let content = I.vcat (List.map (line (max 0 (w - 4)) (attr text)) help_rows) |> I.hpad 1 1 in
    paint ((cols - w) / 2) ((rows - h) / 2)
      (border w h ~title:"Help" ~color:accent ~focused:true content);
    hits := []);
  {image = fit cols rows !canvas; hits = !hits}

let mouse t frame ~now = function
  | `Press `Left, (x, y), _ ->
      if not t.help && t.input = Normal then (
        match hit_at frame x y with
        | Some (Select id) ->
            let double = match t.last_click with Some (previous, time) -> previous = id && now -. time < 0.4 | None -> false in
            act t (Select id); t.last_click <- Some (id, now);
            if double then (t.last_click <- None; act t Zoom)
        | Some action -> t.last_click <- None; act t action
        | None -> t.last_click <- None)
  | `Press (`Scroll direction), (x, y), _ ->
      if not t.help && t.input = Normal then (
        (match hit_at frame x y with Some (Focus focus) -> t.focus <- focus | Some (Select _) -> t.focus <- Board | _ -> ());
        let delta = if direction = `Up then -1 else 1 in
        if t.focus = Board && not t.zoom then t.board_scroll <- max 0 (t.board_scroll + delta)
        else t.scroll <- max 0 (t.scroll + (if t.focus = Activity then delta else -delta) * 3))
  | _ -> ()
