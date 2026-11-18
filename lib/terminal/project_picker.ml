type t = {
  form : Workspace_form.t;
  projects : Project.t list;
  mutable query : Text_edit.t;
  mutable index : int;
  mutable page : int;
}

let create ~form projects =
  { form; projects; query = Text_edit.create ""; index = 0; page = 1 }

let form t = t.form
let query t = Text_edit.text t.query

let visible t =
  let search = Literal_search.prepare (query t) in
  List.filter
    (fun (project : Project.t) ->
      List.exists
        (Literal_search.contains search)
        [ project.name; project.description; project.source ])
    t.projects

let selected t = List.nth_opt (visible t) t.index
let index t = t.index
let capacity t page = t.page <- max 1 page

let move t delta =
  t.index <- max 0 (min (max 0 (List.length (visible t) - 1)) (t.index + delta))

let insert t value =
  let value = Terminal_text.line value in
  if String.length (query t) + String.length value <= 256 then (
    t.query <- Text_edit.insert t.query value;
    t.index <- 0)

let key t (key, mods) =
  match key with
  | `Arrow `Up -> move t (-1)
  | `Arrow `Down -> move t 1
  | `Page `Up -> move t (-t.page)
  | `Page `Down -> move t t.page
  | `Backspace ->
      t.query <- Text_edit.backspace t.query;
      t.index <- 0
  | `Delete ->
      t.query <- Text_edit.delete t.query;
      t.index <- 0
  | `Arrow `Left -> t.query <- Text_edit.left t.query
  | `Arrow `Right -> t.query <- Text_edit.right t.query
  | `ASCII char when mods = [] || mods = [ `Shift ] -> insert t (String.make 1 char)
  | `Uchar char when mods = [] || mods = [ `Shift ] ->
      let buffer = Buffer.create 4 in
      Uutf.Buffer.add_utf_8 buffer char;
      insert t (Buffer.contents buffer)
  | _ -> ()
