type config = {
  executable : string;
  arguments : string list;
  directory : string;
  timeout : float;
  max_line : int;
  max_stream : int;
  max_events : int;
}

type outcome = {
  status : Unix.process_status;
  succeeded : bool;
  interrupted : bool;
  events : int;
  stdout_bytes : int;
  stderr_bytes : int;
}

external spawn : string -> string array -> Unix.file_descr array -> string -> int
  = "factory_spawn"

external monotonic : unit -> float = "factory_monotonic"

let defaults ~executable ~arguments ~directory =
  {
    executable;
    arguments;
    directory;
    timeout = 300.;
    max_line = 1048576;
    max_stream = 16777216;
    max_events = 100000;
  }

exception Process_error of string

let invalid text = String.contains text '\000'

let validate config prompt =
  if
    Filename.is_relative config.executable
    || Filename.is_relative config.directory
    || invalid config.executable || invalid config.directory
    || List.exists invalid config.arguments
  then
    raise
      (Process_error
         "Harness executable and directory must be absolute paths without null bytes.");
  if String.length prompt > 1048576 then raise (Process_error "Prompt exceeds 1 MiB.");
  if
    (not (Float.is_finite config.timeout))
    || config.timeout <= 0. || config.max_line < 1 || config.max_line > 1048576
    || config.max_stream < 1 || config.max_stream > 16777216 || config.max_events < 1
    || config.max_events > 100000
  then raise (Process_error "Invalid harness resource limits.");
  if not (Sys.is_directory config.directory) then
    raise (Process_error "Harness directory does not exist.")

let close fd = try Unix.close fd with Unix.Unix_error _ -> ()

let kill_group pid =
  try
    Unix.kill (-pid) Sys.sigkill;
    true
  with
  | Unix.Unix_error (Unix.ESRCH, _, _) -> true
  | Unix.Unix_error (Unix.EPERM, _, _) -> false

let wait pid =
  let rec loop () =
    try snd (Unix.waitpid [] pid) with Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
  in
  loop ()

let run config ~prompt ~cancelled ~on_event =
  try
    validate config prompt;
    if cancelled () then raise (Process_error "Run cancelled before process launch.");
    let descriptors = ref [] in
    let pipe () =
      let a, b = Unix.pipe ~cloexec:true () in
      descriptors := a :: b :: !descriptors;
      (a, b)
    in
    Fun.protect
      ~finally:(fun () -> List.iter close !descriptors)
      (fun () ->
        let stdin_read, stdin_write = pipe () in
        let stdout_read, stdout_write = pipe () in
        let stderr_read, stderr_write = pipe () in
        (* Closed parent pipe ends must not be closed again after descriptor reuse. *)
        let release fd =
          close fd;
          descriptors := List.filter (( <> ) fd) !descriptors
        in
        let pid =
          spawn config.executable
            (Array.of_list config.arguments)
            [| stdin_read; stdout_write; stderr_write |]
            config.directory
        in
        let status = ref None in
        let stop_child () =
          let rec signal attempts =
            if (not (kill_group pid)) && !status = None then
              (* macOS can refuse a group signal while the child becomes a zombie. *)
              let found, value = Unix.waitpid [ Unix.WNOHANG ] pid in
              if found <> 0 then status := Some value
              else if attempts > 0 then (
                ignore (Unix.select [] [] [] 0.01);
                signal (attempts - 1))
              else raise (Process_error "Cannot terminate harness process group.")
          in
          signal 50
        in
        let cleanup () =
          if !status = None then (
            stop_child ();
            if !status = None then status := Some (wait pid))
        in
        Fun.protect ~finally:cleanup (fun () ->
            List.iter release [ stdin_read; stdout_write; stderr_write ];
            List.iter Unix.set_nonblock [ stdin_write; stdout_read; stderr_read ];
            let started = monotonic () in
            let input_open = ref true
            and output_open = ref true
            and error_open = ref true in
            let prompt = Bytes.of_string prompt and offset = ref 0 in
            let stdout_bytes = ref 0 and stderr_bytes = ref 0 and events = ref 0 in
            let line = Buffer.create 4096
            and completed = ref false
            and failed = ref false
            and input_requested = ref false
            and stopped = ref false in
            let exit_time = ref None in
            let deliver () =
              let text = Buffer.contents line in
              Buffer.clear line;
              if String.trim text <> "" then (
                incr events;
                if !events > config.max_events then
                  raise (Process_error "Harness event limit exceeded.");
                match Harness.decode text with
                | Error error -> raise (Process_error error)
                | Ok decoded -> (
                    (match decoded.event with
                    | Some Model.Turn_completed -> completed := true
                    | Some (Model.Failed _) -> failed := true
                    | Some (Model.Input_requested _) -> input_requested := true
                    | _ -> ());
                    try on_event decoded
                    with _ -> raise (Process_error "Harness event callback failed.")))
            in
            let receive fd is_stdout =
              let bytes = Bytes.create 8192 in
              let count =
                try Unix.read fd bytes 0 8192
                with
                | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) ->
                  -1
              in
              if count = 0 then (
                if is_stdout then (
                  output_open := false;
                  if Buffer.length line > 0 then deliver ())
                else error_open := false;
                release fd)
              else if count > 0 then (
                let total = if is_stdout then stdout_bytes else stderr_bytes in
                total := !total + count;
                if !total > config.max_stream then
                  raise (Process_error "Harness stream limit exceeded.");
                if is_stdout then
                  for i = 0 to count - 1 do
                    if Bytes.get bytes i = '\n' then deliver ()
                    else (
                      if Buffer.length line >= config.max_line then
                        raise (Process_error "Harness line limit exceeded.");
                      Buffer.add_char line (Bytes.get bytes i))
                  done)
            in
            while !status = None || !output_open || !error_open do
              let now = monotonic () in
              if (not !stopped) && cancelled () then (
                stopped := true;
                stop_child ();
                if !status <> None then exit_time := Some now);
              if now -. started > config.timeout then
                raise (Process_error "Harness timeout exceeded.");
              (if !status = None then
                 let found, value =
                   try Unix.waitpid [ Unix.WNOHANG ] pid
                   with Unix.Unix_error (Unix.EINTR, _, _) -> (0, Unix.WEXITED 0)
                 in
                 if found <> 0 then (
                   status := Some value;
                   exit_time := Some now;
                   (* A completed parent can leave descendants holding its output pipes. *)
                   ignore (kill_group pid)));
              (match !exit_time with
              | Some time when now -. time > 1. ->
                  raise (Process_error "Harness output did not close after process exit.")
              | _ -> ());
              if
                !input_open
                && (!offset = Bytes.length prompt || !status <> None || !stopped)
              then (
                input_open := false;
                release stdin_write);
              let reads =
                (if !output_open then [ stdout_read ] else [])
                @ if !error_open then [ stderr_read ] else []
              in
              let writes = if !input_open then [ stdin_write ] else [] in
              let ready_read, ready_write, _ =
                try Unix.select reads writes [] 0.02
                with Unix.Unix_error (Unix.EINTR, _, _) -> ([], [], [])
              in
              List.iter (fun fd -> receive fd (fd = stdout_read)) ready_read;
              if ready_write <> [] then
                let count =
                  try
                    Unix.write stdin_write prompt !offset
                      (min 8192 (Bytes.length prompt - !offset))
                  with
                  | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _)
                    ->
                      0
                  | Unix.Unix_error (Unix.EPIPE, _, _) ->
                      input_open := false;
                      release stdin_write;
                      0
                in
                offset := !offset + count
            done;
            let status = Option.get !status in
            Ok
              {
                status;
                succeeded =
                  status = Unix.WEXITED 0 && !completed && (not !failed)
                  && (not !input_requested) && not !stopped;
                interrupted = !stopped;
                events = !events;
                stdout_bytes = !stdout_bytes;
                stderr_bytes = !stderr_bytes;
              }))
  with
  | Process_error error -> Error error
  | Failure _ | Unix.Unix_error _ | Sys_error _ ->
      Error "Harness process operation failed."
