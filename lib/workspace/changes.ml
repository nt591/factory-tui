open Scope

type state = Idle | Loading | Patch of string | Error of string

type job = {
  mutex : Mutex.t;
  mutable outcome : (string, string) result option;
  mutable thread : Thread.t option;
}

type t = {
  task_id : string;
  workspace : Model.workspace_ref;
  mutable job : job option;
  mutable state : state;
}

let create ~task_id workspace = { task_id; workspace; job = None; state = Idle }
let task_id t = t.task_id
let state t = t.state

let start t ~jj =
  if t.job <> None then Result.Error "A changes refresh is already running."
  else
    match Workspace.restore t.workspace with
    | Error error ->
        t.state <- Error error;
        Result.Error error
    | Ok workspace ->
        let job = { mutex = Mutex.create (); outcome = None; thread = None } in
        job.thread <-
          Some
            (Thread.create
               (fun () ->
                 let result =
                   try Workspace.diff ~jj workspace
                   with _ -> Result.Error "Changes refresh failed."
                 in
                 Mutex.lock job.mutex;
                 let@ () = on_exit (fun () -> Mutex.unlock job.mutex) in
                 job.outcome <- Some result)
               ());
        t.job <- Some job;
        t.state <- Loading;
        Ok ()

let poll t =
  match t.job with
  | None -> ()
  | Some job -> (
      let outcome =
        Mutex.lock job.mutex;
        let@ () = on_exit (fun () -> Mutex.unlock job.mutex) in
        job.outcome
      in
      match outcome with
      | None -> ()
      | Some outcome ->
          Option.iter Thread.join job.thread;
          t.job <- None;
          t.state <-
            (match outcome with
            | Ok patch -> Patch patch
            | Result.Error error -> Error error))

let close t =
  Option.iter (fun job -> Option.iter Thread.join job.thread) t.job;
  poll t
