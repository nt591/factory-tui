open Scope

type state = Idle | Loading | Models of string list | Error of string

type job = {
  mutex : Mutex.t;
  mutable result : (string list, string) result option;
  mutable thread : Thread.t option;
}

type t = {
  mutable state : state;
  mutable job : job option;
  mutable query : Text_edit.t;
  mutable index : int;
  mutable capacity : int;
}

let create () =
  { state = Idle; job = None; query = Text_edit.create ""; index = 0; capacity = 1 }

let state t = t.state
let query t = Text_edit.text t.query

let reset t =
  t.query <- Text_edit.create "";
  t.index <- 0

let visible t =
  match t.state with
  | Models models ->
      let search = Literal_search.prepare (query t) in
      List.filter (Literal_search.contains search) models
  | _ -> []

let selected t = List.nth_opt (visible t) t.index
let index t = t.index
let capacity t count = t.capacity <- max 1 count

let move t delta =
  t.index <- max 0 (min (max 0 (List.length (visible t) - 1)) (t.index + delta))

let insert t text =
  if String.length (query t) + String.length text <= 256 then (
    t.query <- Text_edit.insert t.query (Terminal_text.line text);
    t.index <- 0)

let key t (key, mods) =
  match key with
  | `Arrow `Up -> move t (-1)
  | `Arrow `Down -> move t 1
  | `Page `Up -> move t (-t.capacity)
  | `Page `Down -> move t t.capacity
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

let poll t =
  match t.job with
  | None -> ()
  | Some job ->
      let result =
        Mutex.lock job.mutex;
        let@ () = on_exit (fun () -> Mutex.unlock job.mutex) in
        job.result
      in
      Option.iter
        (fun result ->
          Option.iter Thread.join job.thread;
          t.job <- None;
          t.state <-
            (match result with
            | Ok models -> Models models
            | Result.Error error -> Error error);
          t.index <- 0)
        result

let refresh t fetch =
  poll t;
  if t.job = None then (
    let job = { mutex = Mutex.create (); result = None; thread = None } in
    t.state <- Loading;
    job.thread <-
      Some
        (Thread.create
           (fun () ->
             let result =
               try fetch ()
               with _ -> Result.Error "Model discovery failed. Diagnostics withheld."
             in
             Mutex.lock job.mutex;
             let@ () = on_exit (fun () -> Mutex.unlock job.mutex) in
             job.result <- Some result)
           ());
    t.job <- Some job)

let close t =
  Option.iter (fun job -> Option.iter Thread.join job.thread) t.job;
  poll t
