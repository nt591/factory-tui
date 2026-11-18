type request = {
  id : string;
  greenfield : bool;
  folder_root : bool;
  jj : string;
  source : string;
  parent : string;
  revision : string;
  model : string;
  instruction : string;
}

type job = {
  mutex : Mutex.t;
  mutable thread : Thread.t option;
  mutable outcome : (Model.task, string) result option;
}

exception Creation_error of string

let unwrap = function Ok value -> value | Error error -> raise (Creation_error error)

let title instruction =
  let buffer = Buffer.create 120 and count = ref 0 in
  Uutf.String.fold_utf_8
    (fun () _ character ->
      if !count < 120 then (
        incr count;
        Uutf.Buffer.add_utf_8 buffer
          (match character with `Uchar u -> u | `Malformed _ -> Uutf.u_rep)))
    () instruction;
  Buffer.contents buffer

let create request =
  try
    if
      request.id = ""
      || not
           (String.for_all
              (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' -> true | _ -> false)
              request.id)
    then raise (Creation_error "Invalid workspace task ID.");
    if (not request.folder_root) && Filename.is_relative request.parent then
      raise (Creation_error "Workspace parent must be absolute.");
    let task =
      Model.make ~id:request.id ~title:"Workspace task" ~repository:request.source
    in
    let task = unwrap (Model.set_model task request.model) in
    let task =
      unwrap
        (Model.send { task with messages = [] } ~id:(request.id ^ "/prompt")
           request.instruction)
    in
    if request.folder_root then (
      if
        request.greenfield
        || Filename.is_relative request.source
        || String.exists (fun c -> Char.code c < 32 || Char.code c = 127) request.source
      then
        raise
          (Creation_error "Choose a single creation mode and an absolute session folder.");
      let root = Unix.realpath request.source in
      if not (Sys.is_directory root) then
        raise (Creation_error "Session root must be an existing folder.");
      let task = unwrap (Model.attach_root task root) in
      Ok { task with title = title request.instruction })
    else
      let parent = Unix.realpath request.parent in
      let destination = Filename.concat parent ("factory-" ^ request.id) in
      let workspace =
        unwrap
          (if request.greenfield then
             Workspace.create_greenfield ~jj:request.jj ~destination
           else
             Workspace.create ~jj:request.jj ~source:request.source ~destination
               ~revision:request.revision)
      in
      Model.attach_workspace
        { task with title = title request.instruction }
        (Workspace.reference workspace)
  with
  | Creation_error error -> Error error
  | Unix.Unix_error _ | Sys_error _ ->
      Error "Cannot inspect workspace parent. It must already exist."

let start request =
  let job = { mutex = Mutex.create (); thread = None; outcome = None } in
  job.thread <-
    Some
      (Thread.create
         (fun () ->
           let outcome =
             try create request
             with _ ->
               Error
                 "Workspace creation failed. Retain any partial destination for \
                  inspection."
           in
           Mutex.lock job.mutex;
           job.outcome <- Some outcome;
           Mutex.unlock job.mutex)
         ());
  job

let result job =
  Mutex.lock job.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock job.mutex) (fun () -> job.outcome)

let close job = Option.iter Thread.join job.thread
