open Scope

type batch = { snapshot : Snapshot.t; events : Model.envelope list; generation : int }

type t = {
  mutex : Mutex.t;
  changed : Condition.t;
  mutable thread : Thread.t option;
  mutable initialized : bool;
  mutable loaded : Snapshot.t option;
  mutable pending : batch option;
  mutable submitted : int;
  mutable saved : int;
  mutable failure : string option;
  mutable stopping : bool;
  mutable closed : bool;
}

let locked t fn =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) fn

let fail t message =
  locked t (fun () ->
      t.failure <- Some message;
      t.initialized <- true;
      t.pending <- None;
      Condition.broadcast t.changed)

let worker t path =
  try
    match Storage.open_store path with
    | Error message -> fail t message
    | Ok store -> (
        let@ () = on_exit (fun () -> Storage.close store) in
        match Storage.load store with
        | Error message -> fail t message
        | Ok loaded ->
            locked t (fun () ->
                t.loaded <- loaded;
                t.initialized <- true;
                Condition.broadcast t.changed);
            let rec loop () =
              let batch =
                locked t (fun () ->
                    while t.pending = None && not t.stopping do
                      Condition.wait t.changed t.mutex
                    done;
                    let batch = t.pending in
                    t.pending <- None;
                    batch)
              in
              match batch with
              | None -> ()
              | Some batch -> (
                  match Storage.save store batch.snapshot ~events:batch.events with
                  | Error message -> fail t message
                  | Ok () ->
                      locked t (fun () ->
                          t.saved <- batch.generation;
                          Condition.broadcast t.changed);
                      loop ())
            in
            loop ())
  with _ -> fail t "Persistence worker failed. Conversation data was not printed."

let start path =
  let t =
    {
      mutex = Mutex.create ();
      changed = Condition.create ();
      thread = None;
      initialized = false;
      loaded = None;
      pending = None;
      submitted = 0;
      saved = 0;
      failure = None;
      stopping = false;
      closed = false;
    }
  in
  let thread = Thread.create (worker t) path in
  t.thread <- Some thread;
  let result =
    locked t (fun () ->
        while not t.initialized do
          Condition.wait t.changed t.mutex
        done;
        match t.failure with Some message -> Error message | None -> Ok (t, t.loaded))
  in
  (match result with Error _ -> Thread.join thread | Ok _ -> ());
  result

let submit t snapshot ~events =
  locked t (fun () ->
      if t.stopping || t.closed then Error "Persistence worker is closed."
      else
        match t.failure with
        | Some message -> Error message
        | None ->
            let previous =
              match t.pending with None -> [] | Some batch -> batch.events
            in
            if List.length previous + List.length events > 1024 then
              Error "Persistence event queue is full."
            else (
              t.submitted <- t.submitted + 1;
              (* Snapshot coalescing must not discard ordered events. *)
              t.pending <-
                Some { snapshot; events = previous @ events; generation = t.submitted };
              Condition.signal t.changed;
              Ok ()))

let flush t =
  locked t (fun () ->
      let target = t.submitted in
      while t.saved < target && t.failure = None do
        Condition.wait t.changed t.mutex
      done;
      match t.failure with Some message -> Error message | None -> Ok ())

let error t = locked t (fun () -> t.failure)

let close t =
  locked t (fun () ->
      t.stopping <- true;
      Condition.broadcast t.changed);
  Option.iter Thread.join t.thread;
  locked t (fun () -> t.closed <- true);
  flush t
