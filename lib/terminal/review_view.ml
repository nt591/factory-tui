open Notty

type action = Review_controls.action =
  | Refresh
  | Edit_executable
  | Close
  | Next_file
  | Previous_file

type hit = { x : int; y : int; width : int; action : action }
type scroll_region = { x : int; y : int; width : int; height : int }
type t = { image : Notty.image; hits : hit list; scroll_region : scroll_region option }

let render review ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let attr color = A.(fg color ++ bg background) in
  let row color text =
    I.(string (attr color) (Terminal_text.line text) |> hsnap ~align:`Left cols)
  in
  let capacity = max 0 (rows - 6) in
  Review.set_page_rows review capacity;
  let document =
    match Review.state review with
    | Changes.Patch patch when patch <> "" -> Review.document review
    | _ -> None
  in
  let messages = Review_notice.rows ~width:cols (Review.state review) in
  let line_count =
    Option.fold ~none:(List.length messages) ~some:Diff_document.line_count document
  in
  Review.set_notice_rows review (List.length messages);
  let display = Option.bind document (fun _ -> Review.display review) in
  let widest = Option.fold ~none:0 ~some:Diff_display.widest display in
  Review.set_horizontal review (min (Review.horizontal review) (max 0 (widest - cols)));
  (* File jumps keep the header at the top, including a short final file. *)
  Review.set_scroll review (min (Review.scroll review) (max 0 (line_count - 1)));
  let visible =
    Option.fold
      ~none:
        (List.filteri
           (fun i _ -> i >= Review.scroll review && i < Review.scroll review + capacity)
           messages
        |> List.map Terminal_text.line)
      ~some:(fun display ->
        Diff_display.lines display ~start:(Review.scroll review) ~count:capacity)
      display
  in
  let color text =
    if String.starts_with ~prefix:"+" text then A.lightgreen
    else if String.starts_with ~prefix:"-" text then A.lightred
    else if String.starts_with ~prefix:"@@" text then A.lightcyan
    else A.white
  in
  let body =
    I.(
      vcat
        (List.map
           (fun text ->
             let image = string (attr (color text)) text in
             image |> hcrop (Review.horizontal review) 0 |> hsnap ~align:`Left cols)
           visible)
      |> vsnap ~align:`Top capacity)
  in
  let executable_row =
    if Review.editing review then
      let before, after = Review.executable_cursor_parts review in
      " jj: "
      ^ Text_layout.cursor_window
          (max 0 (cols - 5))
          ~before:(Terminal_text.line before) ~after:(Terminal_text.line after)
    else " jj: " ^ Review.executable review ^ "  [i edits / Enter refreshes]"
  in
  let file_navigation =
    (not (Review.editing review))
    && Option.fold ~none:false
         ~some:(fun document -> Diff_document.file_count document > 1)
         document
  in
  let controls =
    Review_controls.make ~width:cols ~editing:(Review.editing review)
      ~files:file_navigation
  in
  let file_position =
    Option.fold ~none:""
      ~some:(fun document ->
        match Diff_document.file_at document ~line:(Review.scroll review) with
        | None -> ""
        | Some file ->
            Printf.sprintf " · file %d/%d: %s" (file.index + 1)
              (Diff_document.file_count document)
              file.name)
      (Review.document review)
  in
  let image =
    I.vcat
      [
        row A.lightcyan
          (" CHANGES / " ^ Review.task_id review ^ " / " ^ Review.title review);
        row A.lightyellow
          " Refresh snapshots the workspace. No merge, push, deletion, or acceptance.";
        row A.white executable_row;
        body;
        row A.lightyellow
          (Option.value
             ~default:
               (Printf.sprintf " Line %d / %d · column +%d%s"
                  (if line_count = 0 then 0 else Review.scroll review + 1)
                  line_count (Review.horizontal review)
                  (file_position ^ if widest > cols then " · h/l: long lines" else ""))
             (Review.status review));
        row A.lightcyan controls.text;
        row A.white
          (if Review.editing review then
             " Arrows/Home/End: edit path · Enter: refresh · Esc: chat · paste never \
              refreshes"
           else
             " h/l: horizontal · j/k: scroll · Ctrl-U/D: half · Ctrl-B/F: page · [/]: \
              files");
      ]
  in
  let hits = ref [] in
  if rows >= 6 then (
    hits := { x = 1; y = 2; width = max 0 (cols - 2); action = Edit_executable } :: !hits;
    List.iter
      (fun (item : Review_controls.hit) ->
        hits :=
          { x = item.x; y = rows - 2; width = item.width; action = item.action } :: !hits)
      controls.hits);

  {
    image =
      I.(
        image |> hsnap cols |> vsnap ~align:`Top rows
        </> char (attr A.white) ' ' cols rows);
    hits = List.filter (fun (hit : hit) -> hit.width > 0) !hits;
    scroll_region =
      (if capacity = 0 || Review.editing review then None
       else Some { x = 0; y = 3; width = cols; height = capacity });
  }
