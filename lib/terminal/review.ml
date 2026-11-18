type t = {
  task_id : string;
  title : string;
  changes : Changes.t;
  mutable executable : Text_edit.t;
  mutable editing : bool;
  mutable scroll : int;
  mutable horizontal : int;
  mutable error : string option;
  mutable document : Diff_document.t option;
  mutable display : Diff_display.t option;
  mutable page_rows : int;
  mutable notice_rows : int;
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
          document = None;
          display = None;
          page_rows = 10;
          notice_rows = 0;
        }

let task_id t = t.task_id
let title t = t.title
let executable t = Text_edit.text t.executable

let executable_cursor_parts t =
  let text = Text_edit.text t.executable and cursor = Text_edit.cursor t.executable in
  (String.sub text 0 cursor, String.sub text cursor (String.length text - cursor))

let editing t = t.editing
let state t = Changes.state t.changes
let document t = t.document
let display t = t.display
let set_page_rows t value = t.page_rows <- max 1 value
let set_notice_rows t value = t.notice_rows <- max 0 value
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
        t.horizontal <- 0;
        t.document <- None;
        t.display <- None

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

let jump_file t direction =
  if (not t.editing) && match state t with Changes.Patch _ -> true | _ -> false then
    Option.iter
      (fun document ->
        let target =
          match direction with
          | `Next -> Diff_document.next_file document ~line:t.scroll
          | `Previous -> Diff_document.previous_file document ~line:t.scroll
        in
        Option.iter
          (fun (file : Diff_document.file) ->
            t.scroll <- file.line;
            t.horizontal <- 0)
          target)
      t.document

let key t (key, mods) =
  let key =
    match key with
    | `ASCII char when List.mem `Ctrl mods -> `ASCII (Char.lowercase_ascii char)
    | key -> key
  in
  if t.editing then
    match key with
    | `Enter when mods = [] -> refresh t
    | _ when mods = [] || mods = [ `Shift ] -> input t key
    | _ -> ()
  else if mods = [ `Ctrl ] then
    let delta =
      match key with
      | `ASCII 'u' -> Some (-max 1 (t.page_rows / 2))
      | `ASCII 'd' -> Some (max 1 (t.page_rows / 2))
      | `ASCII 'b' -> Some (-t.page_rows)
      | `ASCII 'f' -> Some t.page_rows
      | _ -> None
    in
    Option.iter (fun delta -> set_scroll t (t.scroll + delta)) delta
  else if mods <> [] && mods <> [ `Shift ] then ()
  else
    match key with
    | `ASCII 'r' | `Enter -> refresh t
    | `ASCII 'i' -> edit_executable t
    | `ASCII 'h' | `Arrow `Left -> set_horizontal t (t.horizontal - 4)
    | `ASCII 'l' | `Arrow `Right -> set_horizontal t (t.horizontal + 4)
    | `ASCII '0' -> set_horizontal t 0
    | `ASCII ']' -> jump_file t `Next
    | `ASCII '[' -> jump_file t `Previous
    | `ASCII 'j' | `Arrow `Down -> set_scroll t (t.scroll + 1)
    | `ASCII 'k' | `Arrow `Up -> set_scroll t (t.scroll - 1)
    | `Page `Down -> set_scroll t (t.scroll + t.page_rows)
    | `Page `Up -> set_scroll t (t.scroll - t.page_rows)
    | `Home | `ASCII 'g' -> set_scroll t 0
    | `End | `ASCII 'G' ->
        let total =
          max t.notice_rows
            (Option.fold ~none:0 ~some:Diff_document.line_count t.document)
        in
        set_scroll t (total - t.page_rows)
    | _ -> ()

let paste_key t (key, _) = if t.editing then input t key

let poll t =
  Changes.poll t.changes;
  match (state t, t.document) with
  | Changes.Patch patch, None ->
      let document = Diff_document.parse patch in
      t.document <- Some document;
      t.display <- Some (Diff_display.create document)
  | Changes.Patch _, Some _ -> ()
  | _ ->
      t.document <- None;
      t.display <- None

let close t = Changes.close t.changes
