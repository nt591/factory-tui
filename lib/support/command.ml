open Scope

type output = { status : Unix.process_status; stdout : string; stderr_bytes : int }

external monotonic : unit -> float = "factory_monotonic"
external no_sigpipe : Unix.file_descr -> unit = "factory_socket_no_sigpipe"

external send_input : Unix.file_descr -> bytes -> int -> int -> int
  = "factory_socket_send"

exception Command_error of string

let close fd = try Unix.close fd with Unix.Unix_error _ -> ()

let signal pid =
  try Unix.kill (-pid) Sys.sigkill
  with Unix.Unix_error ((Unix.ESRCH | Unix.EPERM), _, _) -> ()

let reap pid =
  let rec loop () =
    try snd (Unix.waitpid [] pid) with Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
  in
  loop ()

let execute ~input_text ~executable ~arguments ~directory ~timeout ~max_output =
  try
    if
      Filename.is_relative executable
      || Filename.is_relative directory
      || String.contains executable '\000'
      || String.contains directory '\000'
      || List.exists (fun arg -> String.contains arg '\000') arguments
    then
      raise
        (Command_error
           "Command paths must be absolute and arguments must not contain null bytes.");
    if
      timeout <= 0.
      || (not (Float.is_finite timeout))
      || max_output < 1 || max_output > 2097152
      || Option.fold ~none:false
           ~some:(fun text -> String.length text > 1048576)
           input_text
    then raise (Command_error "Invalid command limits.");
    let descriptors = ref [] in
    let pipe () =
      let a, b = Spawn.safe_pipe () in
      descriptors := a :: b :: !descriptors;
      (a, b)
    in
    let release fd =
      close fd;
      descriptors := List.filter (( <> ) fd) !descriptors
    in
    let@ () = on_exit (fun () -> List.iter close !descriptors) in
    let output_read, output_write = pipe () and error_read, error_write = pipe () in
    let input, input_write =
      match input_text with
      | None ->
          let fd = Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
          descriptors := fd :: !descriptors;
          (fd, None)
      | Some _ ->
          let read, write = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
          descriptors := read :: write :: !descriptors;
          Unix.set_close_on_exec read;
          Unix.set_close_on_exec write;
          no_sigpipe write;
          (read, Some write)
    in
    let pending_input = ref input_write in
    let input_offset = ref 0 in
    let input_bytes = Bytes.of_string (Option.value ~default:"" input_text) in
    let close_input () =
      Option.iter release !pending_input;
      pending_input := None
    in
    let pid =
      Spawn.spawn ~prog:executable ~argv:(executable :: arguments)
        ~cwd:(Spawn.Working_dir.Path directory) ~stdin:input ~stdout:output_write
        ~stderr:error_write ~setpgid:Spawn.Pgid.new_process_group ()
    in
    let status = ref None in
    let@ () =
      on_exit (fun () ->
          if !status = None then (
            signal pid;
            status := Some (reap pid)))
    in
    List.iter release [ input; output_write; error_write ];
    List.iter Unix.set_nonblock [ output_read; error_read ];
    Option.iter Unix.set_nonblock input_write;
    let output_open = ref true and error_open = ref true in
    let output = Buffer.create 4096 and error_bytes = ref 0 in
    let started = monotonic () and exited = ref None in
    let receive fd stdout =
      let bytes = Bytes.create 8192 in
      let count =
        try Unix.read fd bytes 0 8192
        with Unix.Unix_error ((Unix.EINTR | Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> -1
      in
      if count = 0 then (
        if stdout then output_open := false else error_open := false;
        release fd)
      else if count > 0 then (
        let total =
          if stdout then Buffer.length output + count else !error_bytes + count
        in
        if total > max_output then raise (Command_error "Command output limit exceeded.");
        if stdout then Buffer.add_subbytes output bytes 0 count else error_bytes := total)
    in
    while !status = None || !output_open || !error_open do
      let now = monotonic () in
      if now -. started > timeout then raise (Command_error "Command timeout exceeded.");
      (if !status = None then
         let found, value =
           try Unix.waitpid [ Unix.WNOHANG ] pid
           with Unix.Unix_error (Unix.EINTR, _, _) -> (0, Unix.WEXITED 0)
         in
         if found <> 0 then (
           status := Some value;
           close_input ();
           exited := Some now;
           signal pid));
      (match !exited with
      | Some time when now -. time > 1. ->
          raise (Command_error "Command output did not close after exit.")
      | _ -> ());
      let reads =
        (if !output_open then [ output_read ] else [])
        @ if !error_open then [ error_read ] else []
      in
      if !input_offset = Bytes.length input_bytes then close_input ();
      let writes = Option.to_list !pending_input in
      let ready, writable, _ =
        try Unix.select reads writes [] 0.02
        with Unix.Unix_error (Unix.EINTR, _, _) -> ([], [], [])
      in
      List.iter (fun fd -> receive fd (fd = output_read)) ready;
      List.iter
        (fun fd ->
          let count =
            try
              send_input fd input_bytes !input_offset
                (min 8192 (Bytes.length input_bytes - !input_offset))
            with
            | Unix.Unix_error ((Unix.EINTR | Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> 0
            | Unix.Unix_error ((Unix.EPIPE | Unix.ECONNRESET), _, _) ->
                close_input ();
                0
          in
          input_offset := !input_offset + count)
        writable
    done;
    Ok
      {
        status = Option.get !status;
        stdout = Buffer.contents output;
        stderr_bytes = !error_bytes;
      }
  with
  | Command_error error -> Error error
  | Unix.Unix_error _ | Sys_error _ | Failure _ ->
      Error "Command process operation failed."

let run ~executable ~arguments ~directory ~timeout ~max_output =
  execute ~input_text:None ~executable ~arguments ~directory ~timeout ~max_output

let run_input ~input ~executable ~arguments ~directory ~timeout ~max_output =
  execute ~input_text:(Some input) ~executable ~arguments ~directory ~timeout ~max_output
