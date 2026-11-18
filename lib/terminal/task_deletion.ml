type t = { id : string; title : string; mutable confirmed : bool }
type result = Edit | Cancel | Confirm

let create (task : Model.task) = { id = task.id; title = task.title; confirmed = false }
let id t = t.id
let ready t = t.confirmed

(* Pasted input cannot confirm task deletion. *)
let insert _ _ = ()

let key t (key, mods) =
  match (key, mods) with
  | (`Escape | `ASCII 'n' | `ASCII 'N'), ([] | [ `Shift ]) -> Cancel
  | (`ASCII 'y' | `ASCII 'Y'), ([] | [ `Shift ]) ->
      t.confirmed <- true;
      Confirm
  | _ -> Edit

let rows t =
  [
    t.id ^ " / " ^ t.title;
    "";
    "Delete this task, its chat, drafts and stored run/event history.";
    "This cannot be undone. Workspace files and agent-owned history stay intact.";
    "";
    "Delete this task? y: Yes / n: No / Esc: Cancel";
  ]
