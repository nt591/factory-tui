open Notty

type action = Refresh | Edit_executable | Close
type hit = { x : int; y : int; width : int; action : action }
type t = { image : Notty.image; hits : hit list }

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
  let lines =
    match Review.state review with
    | Changes.Idle -> [ "Press r / Enter to read the workspace diff. No agent starts." ]
    | Changes.Loading -> [ "Reading workspace changes… input remains responsive." ]
    | Changes.Error error ->
        [
          "Changes error: " ^ error;
          "Retain the workspace. i edits jj path; r retries explicitly.";
        ]
    | Changes.Patch "" -> [ "No changes relative to this task's recorded base." ]
    | Changes.Patch patch -> String.split_on_char '\n' patch
  in
  let patch = match Review.state review with Changes.Patch _ -> true | _ -> false in
  let widest =
    if patch then
      List.fold_left
        (fun widest text -> max widest (I.width (I.string A.empty (clean text))))
        0 lines
    else 0
  in
  Review.set_horizontal review (min (Review.horizontal review) (max 0 (widest - cols)));
  Review.set_scroll review
    (min (Review.scroll review) (max 0 (List.length lines - capacity)));
  let visible =
    List.filteri
      (fun i _ -> i >= Review.scroll review && i < Review.scroll review + capacity)
      lines
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
             let image = string (attr (color text)) (clean text) in
             image |> hcrop (Review.horizontal review) 0 |> hsnap ~align:`Left cols)
           visible)
      |> vsnap ~align:`Top capacity)
  in
  let executable = Review.executable review ^ if Review.editing review then "▏" else "" in
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
                  (if lines = [] then 0 else Review.scroll review + 1)
                  (List.length lines) (Review.horizontal review)
                  (if widest > cols then " · h/l to inspect long lines" else ""))
             (Review.status review));
        row A.lightcyan " [Refresh / r]  [jj path / i]  [Close / Esc]";
        row A.white
          " h/l: horizontal · 0: line start · j/k: scroll · g/G: top/bottom · Esc: chat";
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
          { x = 31; y = rows - 2; width = min 14 (cols - 31); action = Close } :: !hits));
  {
    image =
      I.(
        image |> hsnap cols |> vsnap ~align:`Top rows
        </> char (attr A.white) ' ' cols rows);
    hits = List.filter (fun hit -> hit.width > 0) !hits;
  }
