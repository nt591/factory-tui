type t = {
  task_id : string;
  title : string;
  changes : Changes.t;
  mutable executable : Text_edit.t;
  mutable editing : bool;
  mutable scroll : int;
  mutable horizontal : int;
  mutable error : string option;
}

let create (task : Model.task) ~jj =
  match task.workspace with
  | None -> Error "Task has no workspace. Create one with W to review real changes."
  | Some workspace ->
      Ok
        {
          task_id = task.id;
          title = task.title;
          changes = Changes.create ~task_id:task.id workspace;
          executable = Text_edit.create jj;
          editing = jj = "";
          scroll = 0;
          horizontal = 0;
          error = None;
        }

let task_id t = t.task_id
let title t = t.title
let executable t = Text_edit.text t.executable
let editing t = t.editing
let state t = Changes.state t.changes
let scroll t = t.scroll
let set_scroll t value = t.scroll <- max 0 (min 1000000 value)
let horizontal t = t.horizontal
let set_horizontal t value = t.horizontal <- max 0 (min 2097152 value)

let refresh t =
  let jj = executable t in
  if
    jj = "" || Filename.is_relative jj
    || String.exists (fun c -> Char.code c < 32 || Char.code c = 127) jj
  then t.error <- Some "Enter an absolute jj executable path."
  else
    match Changes.start t.changes ~jj with
    | Error error -> t.error <- Some error
    | Ok () ->
        t.error <- None;
        t.editing <- false;
        t.scroll <- 0;
        t.horizontal <- 0

let status t = t.error
let edit_executable t = if state t <> Changes.Loading then t.editing <- true

let input t key =
  match key with
  | `Backspace -> t.executable <- Text_edit.backspace t.executable
  | `Delete -> t.executable <- Text_edit.delete t.executable
  | `Arrow `Left -> t.executable <- Text_edit.left t.executable
  | `Arrow `Right -> t.executable <- Text_edit.right t.executable
  | `Home -> t.executable <- Text_edit.home t.executable
  | `End -> t.executable <- Text_edit.ending t.executable
  | `ASCII char ->
      if Char.code char >= 32 && Char.code char <> 127 then
        t.executable <- Text_edit.insert t.executable (String.make 1 char)
  | `Uchar u ->
      let buffer = Buffer.create 4 in
      Uutf.Buffer.add_utf_8 buffer u;
      t.executable <- Text_edit.insert t.executable (Buffer.contents buffer)
  | _ -> ()

let key t (key, mods) =
  if t.editing then
    match key with
    | `Enter -> refresh t
    | _ when mods = [] || mods = [ `Shift ] -> input t key
    | _ -> ()
  else
    match key with
    | `ASCII 'r' | `Enter -> refresh t
    | `ASCII 'i' -> edit_executable t
    | `ASCII 'h' | `Arrow `Left -> set_horizontal t (t.horizontal - 4)
    | `ASCII 'l' | `Arrow `Right -> set_horizontal t (t.horizontal + 4)
    | `ASCII '0' -> set_horizontal t 0
    | `ASCII 'j' | `Arrow `Down -> set_scroll t (t.scroll + 1)
    | `ASCII 'k' | `Arrow `Up -> set_scroll t (t.scroll - 1)
    | `Page `Down -> set_scroll t (t.scroll + 10)
    | `Page `Up -> set_scroll t (t.scroll - 10)
    | `Home | `ASCII 'g' -> set_scroll t 0
    | `End | `ASCII 'G' -> set_scroll t 1000000
    | _ -> ()

let paste_key t (key, _) = if t.editing then input t key
let poll t = Changes.poll t.changes
let close t = Changes.close t.changes
