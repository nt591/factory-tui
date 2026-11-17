type t = {
  mutex : Mutex.t;
  queue : Harness.decoded Queue.t;
  capacity : int;
  mutable cancelled : bool;
  mutable overflow : bool;
  mutable outcome : (Process.outcome, string) result option;
  mutable thread : Thread.t option;
}

let locked t fn =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) fn

let cancel t = locked t (fun () -> t.cancelled <- true)

let start ?(capacity = 128) ?(checkpoint = fun () -> Ok ()) config ~prompt =
  if capacity < 1 || capacity > 1024 then invalid_arg "Invalid run delivery capacity.";
  let t =
    {
      mutex = Mutex.create ();
      queue = Queue.create ();
      capacity;
      cancelled = false;
      overflow = false;
      outcome = None;
      thread = None;
    }
  in
  let cancelled () = locked t (fun () -> t.cancelled) in
  let on_event decoded =
    locked t (fun () ->
        if Queue.length t.queue >= t.capacity then (
          t.overflow <- true;
          t.cancelled <- true;
          failwith "Run delivery queue is full.")
        else Queue.push decoded t.queue)
  in
  let worker () =
    let result =
      try
        match checkpoint () with
        | Error error -> Error error
        | Ok () -> Process.run config ~prompt ~cancelled ~on_event
      with _ -> Error "Run checkpoint failed."
    in
    locked t (fun () ->
        (* Completion has separate storage so a full queue cannot discard it. *)
        t.outcome <-
          Some
            (if t.overflow then Error "Run delivery queue overflow; process cancelled."
             else result))
  in
  t.thread <- Some (Thread.create worker ());
  t

let drain t =
  locked t (fun () ->
      let events = ref [] in
      while not (Queue.is_empty t.queue) do
        events := Queue.pop t.queue :: !events
      done;
      List.rev !events)

let outcome t = locked t (fun () -> t.outcome)

let close t =
  cancel t;
  Option.iter Thread.join t.thread
