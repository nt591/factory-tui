type field = Jj | Source | Parent | Revision | Model | Task
type feedback = Guidance of string | Validation of field * string | Report of string

type t = {
  mutable current : field;
  mutable values : (field * Text_edit.t) list;
  mutable status : feedback;
  mutable rejected : field option;
}

let fields = [ Jj; Source; Parent; Revision; Model; Task ]

let label = function
  | Jj -> "jj executable"
  | Source -> "Source repository"
  | Parent -> "Workspace parent"
  | Revision -> "Base revision"
  | Model -> "Next-run model"
  | Task -> "Task instruction"

let create ?(jj = "") ~source ~parent ~revision ~model () =
  {
    current = Source;
    rejected = None;
    status = Guidance "Fill the fields; Ctrl-S creates a queued task. No agent starts.";
    values =
      [
        (Jj, Text_edit.create jj);
        (Source, Text_edit.create source);
        (Parent, Text_edit.create parent);
        (Revision, Text_edit.create revision);
        (Model, Text_edit.create model);
        (Task, Text_edit.create "");
      ];
  }

let current t = t.current

let status t =
  let feedback =
    match t.status with Guidance text | Validation (_, text) | Report text -> text
  in
  match t.rejected with
  | None -> feedback
  | Some field -> label field ^ ": Edit not applied / 64 KiB limit. " ^ feedback

let report t text =
  match t.status with
  | Validation (_, error) when error = text -> ()
  | _ -> t.status <- Report text

let editor t field = List.assoc field t.values
let value t field = Text_edit.text (editor t field)

let cursor_parts t field =
  let editor = editor t field in
  let text = Text_edit.text editor and cursor = Text_edit.cursor editor in
  (String.sub text 0 cursor, String.sub text cursor (String.length text - cursor))

let focus t field = t.current <- field

let change t fn =
  let previous = editor t t.current in
  let updated = fn previous in
  if Text_edit.text previous <> Text_edit.text updated then (
    if t.rejected = Some t.current then t.rejected <- None;
    match t.status with
    | Validation (field, _) when field = t.current ->
        t.status <- Guidance "Field edited. Ctrl-S checks all fields before creating."
    | _ -> ());
  t.values <- (t.current, updated) :: List.remove_assoc t.current t.values

let set_model t value =
  match Model.set_model (Model.make ~id:"validation" ~title:"" ~repository:"") value with
  | Error error -> Error error
  | Ok model ->
      t.current <- Model;
      change t (fun _ -> Text_edit.create model.model);
      Ok ()

let cycle t backwards =
  let order = if backwards then List.rev fields else fields in
  let rec next = function
    | a :: b :: _ when a = t.current -> b
    | _ :: rest -> next rest
    | [] -> List.hd order
  in
  t.current <- next order

let insert t text =
  let text = Terminal_text.line text in
  let previous = editor t t.current in
  let updated = Text_edit.insert previous text in
  if text <> "" && updated == previous then t.rejected <- Some t.current
  else change t (fun _ -> updated)

let key t (key, mods) =
  match key with
  | `Tab -> cycle t (List.mem `Shift mods)
  | `Enter -> cycle t false
  | `Backspace -> change t Text_edit.backspace
  | `Delete -> change t Text_edit.delete
  | `Home -> change t Text_edit.home
  | `End -> change t Text_edit.ending
  | `Arrow `Left -> change t Text_edit.left
  | `Arrow `Right -> change t Text_edit.right
  | `ASCII char when mods = [] || mods = [ `Shift ] -> insert t (String.make 1 char)
  | `Uchar u when mods = [] || mods = [ `Shift ] ->
      let buffer = Buffer.create 4 in
      Uutf.Buffer.add_utf_8 buffer u;
      insert t (Buffer.contents buffer)
  | _ -> ()

let paste_key t (key, _) =
  match key with
  | `Enter -> insert t " "
  | `ASCII char -> insert t (String.make 1 char)
  | `Uchar u ->
      let buffer = Buffer.create 4 in
      Uutf.Buffer.add_utf_8 buffer u;
      insert t (Buffer.contents buffer)
  | _ -> ()

let validation_error t =
  let invalid_path field =
    let path = value t field in
    path = "" || Filename.is_relative path || String.contains path '\000'
  in
  match List.find_opt invalid_path [ Jj; Source; Parent ] with
  | Some field ->
      Some
        (field, label field ^ ": Use absolute paths for jj, source, and workspace parent.")
  | None -> (
      if String.trim (value t Revision) = "" || (value t Revision).[0] = '-' then
        Some (Revision, "Enter an explicit base revision.")
      else
        match
          Model.set_model
            (Model.make ~id:"validation" ~title:"" ~repository:"")
            (value t Model)
        with
        | Error error -> Some (Model, error)
        | Ok _ ->
            if String.trim (value t Task) = "" then
              Some (Task, "Enter a task instruction.")
            else if String.length (value t Task) > 65536 then
              Some (Task, "Task exceeds 64 KiB.")
            else None)

let validate t =
  match validation_error t with None -> Ok () | Some (_, error) -> Error error

let validate_submission t =
  match validation_error t with
  | None -> Ok ()
  | Some (field, error) ->
      t.current <- field;
      t.status <- Validation (field, error);
      Error error
