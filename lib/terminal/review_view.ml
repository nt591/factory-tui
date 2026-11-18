open Notty

type action = Refresh | Edit_executable | Close | Next_file | Previous_file
type hit = { x : int; y : int; width : int; action : action }
type scroll_region = { x : int; y : int; width : int; height : int }
type t = { image : Notty.image; hits : hit list; scroll_region : scroll_region option }

let clean text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          if Uchar.to_int u < 32 || (Uchar.to_int u >= 127 && Uchar.to_int u <= 159) then
            Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let render review ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let attr color = A.(fg color ++ bg background) in
  let row color text = I.(string (attr color) (clean text) |> hsnap ~align:`Left cols) in
  let capacity = max 0 (rows - 6) in
  Review.set_page_rows review capacity;
  let document =
    match Review.state review with
    | Changes.Patch patch when patch <> "" -> Review.document review
    | _ -> None
  in
  let messages =
    match Review.state review with
    | Changes.Idle -> [ "Press r / Enter to read the workspace diff. No agent starts." ]
    | Changes.Loading -> [ "Reading workspace changes… input remains responsive." ]
    | Changes.Error error ->
        [
          "Changes error: " ^ error;
          "Retain the workspace. i edits jj path; r retries explicitly.";
        ]
    | Changes.Patch "" -> [ "No changes relative to this task's recorded base." ]
    | Changes.Patch _ -> []
  in
  let line_count =
    Option.fold ~none:(List.length messages) ~some:Diff_document.line_count document
  in
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
        |> List.map clean)
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
  let executable = Review.executable review ^ if Review.editing review then "▏" else "" in
  let file_navigation =
    (not (Review.editing review))
    && Option.fold ~none:false
         ~some:(fun document -> Diff_document.file_count document > 1)
         document
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
        row A.white (" jj: " ^ executable ^ "  [i edits / Enter refreshes]");
        body;
        row A.lightyellow
          (Option.value
             ~default:
               (Printf.sprintf " Line %d / %d · column +%d%s"
                  (if line_count = 0 then 0 else Review.scroll review + 1)
                  line_count (Review.horizontal review)
                  (file_position ^ if widest > cols then " · h/l: long lines" else ""))
             (Review.status review));
        row A.lightcyan
          (" [Refresh / r]  [jj path / i]  [Close / Esc]"
          ^ if file_navigation then "  [Prev file]  [Next file]" else "");
        row A.white
          " h/l: horizontal · j/k: scroll · g/G: top/bottom · [/]: files · Esc: chat";
      ]
  in
  let hits = ref [] in
  if rows >= 6 then (
    hits := { x = 1; y = 2; width = max 0 (cols - 2); action = Edit_executable } :: !hits;
    if not (Review.editing review) then (
      hits :=
        { x = 1; y = rows - 2; width = min 13 (max 0 (cols - 1)); action = Refresh }
        :: !hits;
      if cols > 16 then
        hits :=
          { x = 16; y = rows - 2; width = min 13 (cols - 16); action = Edit_executable }
          :: !hits;
      if cols > 31 then
        hits :=
          { x = 31; y = rows - 2; width = min 13 (cols - 31); action = Close } :: !hits;
      if file_navigation && cols > 46 then
        hits :=
          { x = 46; y = rows - 2; width = min 11 (cols - 46); action = Previous_file }
          :: !hits;
      if file_navigation && cols > 59 then
        hits :=
          { x = 59; y = rows - 2; width = min 11 (cols - 59); action = Next_file }
          :: !hits));
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
