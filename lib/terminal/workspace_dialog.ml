open Notty

type action =
  | Field of Workspace_form.field
  | Create
  | Cancel
  | Models
  | Projects
  | Greenfield

type hit = { x : int; y : int; width : int; action : action }
type t = { image : Notty.image; hits : hit list }

let render_body form ~busy ~status ~width:cols ~height:rows =
  let cols = max 1 cols and rows = max 1 rows in
  let background = A.rgb_888 ~r:25 ~g:31 ~b:42 in
  let normal = A.(fg white ++ bg background) in
  let accent = A.(fg lightcyan ++ bg background ++ st bold) in
  let warning = A.(fg lightyellow ++ bg background) in
  let row attr text = I.(string attr text |> hsnap ~align:`Left cols) in
  let entries =
    List.concat_map
      (fun field ->
        let focused = Workspace_form.current form = field in
        let attr = if focused then accent else normal in
        let text =
          if focused && not busy then
            let before, after = Workspace_form.cursor_parts form field in
            Text_layout.cursor_window (max 1 (cols - 4)) ~before ~after
          else Text_layout.ellipsize (max 1 (cols - 4)) (Workspace_form.value form field)
        in
        let value =
          I.(
            string attr text
            |> hsnap ~align:`Left (max 1 (cols - 4))
            |> hpad 2 2 |> hsnap cols)
        in
        [
          ( row attr
              (" "
              ^
              if field = Workspace_form.Source && Workspace_form.folder_root form then
                "Session root folder"
              else Workspace_form.label field),
            None );
          (value, Some (Field field));
          (row normal "", None);
        ])
      Workspace_form.fields
  in
  let capacity = max 0 (rows - 7) in
  let rec focus_index i = function
    | [] -> 0
    | (_, Some (Field field)) :: _ when field = Workspace_form.current form -> i
    | _ :: rest -> focus_index (i + 1) rest
  in
  let offset =
    if capacity >= List.length entries then 0
    else max 0 (focus_index 0 entries - capacity + 1)
  in
  let displayed =
    List.filteri (fun i _ -> i >= offset && i < offset + capacity) entries
  in
  let hits = ref [] in
  let images =
    List.mapi
      (fun i (image, action) ->
        if (not busy) && cols > 2 && i + 3 < rows then
          Option.iter
            (fun action ->
              hits := { x = 1; y = i + 3; width = max 1 (cols - 2); action } :: !hits)
            action;
        image)
      displayed
  in
  let fields = I.(vcat images |> vsnap ~align:`Top capacity) in
  let buttons =
    if busy then " Creating workspace… please wait. No agent starts."
    else
      " [Create queued / Ctrl-S]   [Cancel / Esc]  [Models / Ctrl-G] [Projects / Ctrl-P]"
  in
  if (not busy) && rows >= 7 && cols > 2 then (
    hits := { x = 1; y = rows - 2; width = min 25 (cols - 1); action = Create } :: !hits;
    if cols > 28 then
      hits :=
        { x = 28; y = rows - 2; width = min 16 (cols - 28); action = Cancel } :: !hits;
    if cols >= 61 then
      hits := { x = 44; y = rows - 2; width = 17; action = Models } :: !hits;
    if cols >= 81 then
      hits := { x = 62; y = rows - 2; width = 19; action = Projects } :: !hits);
  let image =
    I.vcat
      [
        row accent " NEW WORKSPACE TASK";
        row warning
          (if Workspace_form.folder_root form then
             " Existing folder: no copy or checkout. Write policy affects this folder."
           else " jj can snapshot source files; never fetches, merges, or pushes.");
        row normal
          (if Workspace_form.folder_root form then
             " FOLDER ROOT / Source is working folder; no checkout is created. Ctrl-E \
              switches."
           else if Workspace_form.greenfield form then
             " GREENFIELD / new repository; source and revision are ignored. Ctrl-N \
              switches."
           else " EXISTING PROJECT / Ctrl-N switches to a new repository.");
        fields;
        row normal "";
        row warning status;
        row accent buttons;
        row normal " Ctrl-E: folder root · Ctrl-N: greenfield · Ctrl-S: create";
      ]
  in
  {
    image =
      I.(image |> hsnap cols |> vsnap ~align:`Top rows </> char normal ' ' cols rows);
    hits = !hits;
  }

let render form ~busy ~status ~width ~height =
  if width < 4 || height < 4 then render_body form ~busy ~status ~width ~height
  else
    let body = render_body form ~busy ~status ~width:(width - 2) ~height:(height - 2) in
    let attr = Notty.A.(fg lightcyan ++ bg (rgb_888 ~r:25 ~g:31 ~b:42)) in
    let horizontal = String.concat "" (List.init (width - 2) (fun _ -> "─")) in
    let side = Notty.I.uchar attr (Uchar.of_int 0x2502) 1 (height - 2) in
    let image =
      Notty.I.(
        string attr ("╭" ^ horizontal ^ "╮")
        <-> (side <|> body.image <|> side)
        <-> string attr ("╰" ^ horizontal ^ "╯"))
    in
    {
      image;
      hits = List.map (fun hit -> { hit with x = hit.x + 1; y = hit.y + 1 }) body.hits;
    }
