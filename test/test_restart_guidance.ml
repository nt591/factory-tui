open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let snapshot tasks drafts : Snapshot.t =
  {
    tasks;
    drafts;
    selected = (match tasks with [] -> "" | task :: _ -> task.id);
    serial = 1;
  }

let task id state = { (Model.make ~id ~title:id ~repository:"fixture") with state }

let () =
  let clean = snapshot [ task "ready" Ready; task "done" Done ] [] in
  check "clean restart does not imply interrupted work"
    (Restart_guidance.describe clean
    = "Saved conversations restored. No interrupted runs.");
  let active = Result.get_ok (Model.start (task "active" Queued) "run") in
  let saved = snapshot [ active ] [ (active.id, "Kept draft") ] in
  let text = Restart_guidance.describe saved in
  check "working snapshot reports actual interrupted count"
    (Controller.contains text "1 interrupted run; no agent resumed.");
  check "saved nonempty draft is disclosed"
    (Controller.contains text "1 saved draft retained");
  let multiple =
    snapshot
      [ active; { active with id = "second" } ]
      [ ("active", "one"); ("second", "two"); ("empty", "") ]
  in
  check "multiple count ignores empty drafts"
    (Controller.contains (Restart_guidance.describe multiple) "2 interrupted runs;"
    && Controller.contains (Restart_guidance.describe multiple) "2 saved drafts retained"
    );
  let controller = Controller.create ~external_events:true () in
  Controller.restore controller saved;
  let restored = Option.get (Controller.selected controller) in
  check "actual recovery moves interrupted task to Needs you"
    (restored.state = Needs_you && restored.active = None
    && (List.hd restored.runs).status = Stopped);
  check "restored footer matches pre-recovery snapshot" (controller.status = text);
  check "recovery retains draft and never schedules a process"
    (Controller.draft controller = "Kept draft" && controller.schedules = []);
  Controller.act controller Controller.Begin_compose;
  check "restored draft remains editable" (Text_edit.text controller.editor = "Kept draft");
  Controller.key controller (`Escape, []);
  Controller.restore controller clean;
  check "reopening completed tasks reports no recovery failure"
    (controller.status = "Saved conversations restored. No interrupted runs.");
  check "guidance does not change input snapshots"
    (saved.tasks = [ active ] && saved.drafts = [ (active.id, "Kept draft") ]);
  let archived =
    {
      (snapshot
         [ task "active-board" Queued; task "accepted" Done ]
         [ ("accepted", "Retained read-only draft") ])
      with
      selected = "accepted";
    }
  in
  controller.archive <- false;
  Controller.restore controller archived;
  check "restart retains accepted conversation outside active board"
    (controller.selected = "accepted"
    && (Option.get (Controller.selected controller)).state = Done
    && Controller.draft controller = "Retained read-only draft");
  check "active filter remains independent of restored chat"
    (List.map (fun (task : Model.task) -> task.id) (Controller.visible controller)
    = [ "active-board" ]);
  controller.query <- "no matching tasks";
  Controller.restore controller archived;
  check "empty board filter cannot clear valid restored selection"
    (controller.selected = "accepted");
  let missing = { archived with selected = "deleted" } in
  controller.query <- "";
  Controller.restore controller missing;
  check "missing selected task falls back to first visible card"
    (controller.selected = "active-board");
  controller.query <- "no matching tasks";
  Controller.restore controller missing;
  check "missing selection with empty board still chooses retained conversation"
    (controller.selected = "active-board");
  Controller.restore controller (snapshot [] []);
  check "empty snapshot clears nonexistent conversation"
    (controller.selected = "" && Controller.selected controller = None);
  Printf.printf
    "Passed %d restart guidance checks. Pure snapshots and controller recovery.\n" !checks
