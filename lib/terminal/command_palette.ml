open Model

type command =
  | Board
  | Archive
  | New_task
  | Reply
  | Model
  | Models
  | Stop
  | Accept
  | Restore
  | Delete
  | Review
  | Help

type entry = {
  command : command;
  title : string;
  shortcut : string;
  disabled : string option;
}

type t = {
  mutable entries : entry list;
  mutable editor : Text_edit.t;
  mutable index : int;
}

type result = Edit | Cancel | Execute of command

let catalogue ~task ~live ~replay ~storage ~busy =
  let no_task = if task = None then Some "Select a task first." else None in
  let archived =
    Option.fold ~none:false ~some:(fun (task : task) -> task.state = Done) task
  in
  let writable = if archived then Some "Restore the task first." else no_task in
  let state required =
    match task with
    | None -> no_task
    | Some task ->
        if task.state = required then None
        else Some ("Task must be " ^ label required ^ ".")
  in
  let entry command title shortcut disabled = { command; title; shortcut; disabled } in
  [
    entry Board "Open Board" "b" None;
    entry Archive "Open Archive" "" None;
    entry New_task "New task" "n"
      (if live && not storage then Some "Configure SQLite first." else None);
    entry Reply "Reply to agent" "Enter / i" writable;
    entry Model "Select task model" "m" writable;
    entry Models "Browse gateway models" "M"
      (if not live then Some "Configure a live gateway first." else None);
    entry Stop "Stop task" "x"
      (if replay then Some "Replay does not control a process." else state Working);
    entry Accept "Accept & archive task" "Ctrl-A" (state Ready);
    entry Restore "Restore archived task" "u" (state Done);
    entry Delete "Delete task…" "Ctrl-X"
      (if busy then Some "Stop task and wait for process cleanup." else no_task);
    entry Review "Review workspace changes" "v"
      (match task with
      | Some task when task.workspace <> None -> None
      | _ -> Some "Task needs a recorded workspace.");
    entry Help "Help and settings" "?" None;
  ]

let create entries = { entries; editor = Text_edit.create ""; index = 0 }
let query t = Text_edit.text t.editor
let editor t = t.editor

let visible t =
  let search = Literal_search.prepare (query t) in
  List.filter (fun entry -> Literal_search.contains search entry.title) t.entries

let selected t = List.nth_opt (visible t) t.index
let index t = t.index

let move t delta =
  t.index <- max 0 (min (max 0 (List.length (visible t) - 1)) (t.index + delta))

let update t entries =
  t.entries <- entries;
  move t 0

let edit t fn =
  let editor = fn t.editor in
  if String.length (Text_edit.text editor) <= 256 then (
    t.editor <- editor;
    t.index <- 0)

let insert t text =
  edit t (fun editor -> Text_edit.insert editor (Terminal_text.line text))

let execute t =
  match selected t with
  | Some { command; disabled = None; _ } -> Execute command
  | _ -> Edit

let choose t command =
  match List.find_opt (fun entry -> entry.command = command) (visible t) with
  | Some { disabled = None; _ } -> Execute command
  | _ -> Edit

let key t (key, mods) =
  match key with
  | `Escape -> Cancel
  | `Enter when mods = [] -> execute t
  | (`Arrow `Down | `Tab) when mods = [] ->
      move t 1;
      Edit
  | (`Arrow `Up | `Tab) when mods = [ `Shift ] || mods = [] ->
      move t (-1);
      Edit
  | `Backspace ->
      edit t Text_edit.backspace;
      Edit
  | `Delete ->
      edit t Text_edit.delete;
      Edit
  | `Arrow `Left ->
      edit t Text_edit.left;
      Edit
  | `Arrow `Right ->
      edit t Text_edit.right;
      Edit
  | `Home ->
      edit t Text_edit.home;
      Edit
  | `End ->
      edit t Text_edit.ending;
      Edit
  | `ASCII char when mods = [] || mods = [ `Shift ] ->
      insert t (String.make 1 char);
      Edit
  | `Uchar char when mods = [] || mods = [ `Shift ] ->
      let buffer = Buffer.create 4 in
      Uutf.Buffer.add_utf_8 buffer char;
      insert t (Buffer.contents buffer);
      Edit
  | _ -> Edit
