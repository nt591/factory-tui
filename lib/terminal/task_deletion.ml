type t = { id : string; title : string; mutable text : string }
type result = Edit | Cancel | Confirm

let create (task : Model.task) = { id = task.id; title = task.title; text = "" }
let id t = t.id
let ready t = t.text = "delete"

let insert t value =
  let value = Terminal_text.line value in
  if String.length t.text + String.length value <= 32 then t.text <- t.text ^ value

let key t (key, mods) =
  match key with
  | `Escape -> Cancel
  | `Enter when mods = [] && ready t -> Confirm
  | `Backspace ->
      t.text <- Text_edit.text (Text_edit.backspace (Text_edit.create t.text));
      Edit
  | `ASCII char when mods = [] || mods = [ `Shift ] ->
      insert t (String.make 1 char);
      Edit
  | _ -> Edit

let rows t =
  [
    t.id ^ " / " ^ t.title;
    "";
    "Delete this task, its chat, drafts and stored run/event history.";
    "This cannot be undone. Workspace files and agent-owned history stay intact.";
    "";
    "Type delete and press Enter to confirm. Esc cancels.";
    "Confirm: " ^ t.text ^ "▏";
  ]
