type field = Jj | Source | Parent | Revision | Model | Task
type t = { mutable current : field; mutable values : (field * Text_edit.t) list }

let fields = [ Jj; Source; Parent; Revision; Model; Task ]

let label = function
  | Jj -> "jj executable"
  | Source -> "Source repository"
  | Parent -> "Workspace parent"
  | Revision -> "Base revision"
  | Model -> "Next-run model"
  | Task -> "Task instruction"

let create ~source ~parent ~revision ~model =
  {
    current = Source;
    values =
      [
        (Jj, Text_edit.create "");
        (Source, Text_edit.create source);
        (Parent, Text_edit.create parent);
        (Revision, Text_edit.create revision);
        (Model, Text_edit.create model);
        (Task, Text_edit.create "");
      ];
  }

let current t = t.current
let editor t field = List.assoc field t.values
let value t field = Text_edit.text (editor t field)

let cursor_text t field =
  let editor = editor t field in
  let text = Text_edit.text editor and cursor = Text_edit.cursor editor in
  String.sub text 0 cursor ^ "▏" ^ String.sub text cursor (String.length text - cursor)

let focus t field = t.current <- field

let change t fn =
  t.values <- (t.current, fn (editor t t.current)) :: List.remove_assoc t.current t.values

let cycle t backwards =
  let order = if backwards then List.rev fields else fields in
  let rec next = function
    | a :: b :: _ when a = t.current -> b
    | _ :: rest -> next rest
    | [] -> List.hd order
  in
  t.current <- next order

let sanitize text =
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

let insert t text = change t (fun editor -> Text_edit.insert editor (sanitize text))

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

let validate t =
  let invalid_path field =
    let path = value t field in
    path = "" || Filename.is_relative path || String.contains path '\000'
  in
  if List.exists invalid_path [ Jj; Source; Parent ] then
    Error "Use absolute paths for jj, source, and workspace parent."
  else if String.trim (value t Revision) = "" || (value t Revision).[0] = '-' then
    Error "Enter an explicit base revision."
  else if String.trim (value t Task) = "" then Error "Enter a task instruction."
  else if String.length (value t Task) > 65536 then Error "Task exceeds 64 KiB."
  else
    match
      Model.set_model
        (Model.make ~id:"validation" ~title:"" ~repository:"")
        (value t Model)
    with
    | Error error -> Error error
    | Ok _ -> Ok ()
