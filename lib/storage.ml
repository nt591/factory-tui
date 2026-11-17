type t = { db : Sqlite3.db; lock : Unix.file_descr; path : string; mutable closed : bool }
exception Storage_error of string
let owners = Hashtbl.create 4
let ownership_mutex = Mutex.create ()
let ownership fn =
  Mutex.lock ownership_mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock ownership_mutex) fn
let ensure rc = if rc <> Sqlite3.Rc.OK && rc <> Sqlite3.Rc.DONE then
  raise (Storage_error "SQLite operation failed.")
let exec db sql = ensure (Sqlite3.exec db sql)
let statement db sql fn =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () -> fn stmt)
let protect fn = try Ok (fn ()) with
  | Storage_error error -> Error error
  | Sqlite3.Error _ | Sqlite3.SqliteError _ -> Error "SQLite operation failed."
  | Unix.Unix_error _ | Sys_error _ -> Error "Storage file operation failed."
let canonical path =
  if Filename.is_relative path then raise (Storage_error "Database path must be absolute.");
  Filename.concat (Unix.realpath (Filename.dirname path)) (Filename.basename path)
let regular path =
  try if (Unix.lstat path).Unix.st_kind <> Unix.S_REG then
    raise (Storage_error "Database and lock must be regular files, not symbolic links.")
  with Unix.Unix_error (Unix.ENOENT, _, _) -> ()
let close store = ownership (fun () -> if not store.closed then (
  store.closed <- true;
  ignore (Sqlite3.db_close store.db);
  Hashtbl.remove owners store.path;
  Unix.close store.lock))
let open_store path = ownership (fun () -> protect (fun () ->
  let path = canonical path in
  regular path; regular (path ^ ".lock");
  if Hashtbl.mem owners path then raise (Storage_error "Database is already open.");
  let lock = Unix.openfile (path ^ ".lock") [Unix.O_RDWR; Unix.O_CREAT; Unix.O_CLOEXEC] 0o600 in
  try
    (try Unix.lockf lock Unix.F_TLOCK 0 with Unix.Unix_error _ ->
       raise (Storage_error "Database is already open in another process."));
    let fd = Unix.openfile path [Unix.O_RDWR; Unix.O_CREAT; Unix.O_CLOEXEC] 0o600 in
    Unix.close fd;
    let db = Sqlite3.db_open ~mode:`NO_CREATE path in
    try
      Sqlite3.busy_timeout db 1000;
      let version = statement db "PRAGMA user_version" (fun stmt ->
        if Sqlite3.step stmt <> Sqlite3.Rc.ROW then raise (Storage_error "Cannot read database version.");
        Sqlite3.column_int stmt 0) in
      if version <> 0 && version <> 1 then raise (Storage_error "Unsupported database version.");
      if version = 0 then (
        let count = statement db "SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'" (fun stmt ->
          if Sqlite3.step stmt <> Sqlite3.Rc.ROW then raise (Storage_error "Cannot inspect database.");
          Sqlite3.column_int stmt 0) in
        if count <> 0 then raise (Storage_error "Database belongs to another application.");
        exec db "BEGIN IMMEDIATE";
        (try
          exec db "CREATE TABLE snapshot (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)";
          exec db "CREATE TABLE runs (task_id TEXT NOT NULL, run_id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(task_id,run_id))";
          exec db "CREATE TABLE events (sequence INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)";
          exec db "PRAGMA user_version=1";
          exec db "COMMIT"
        with error -> ignore (Sqlite3.exec db "ROLLBACK"); raise error));
      exec db "PRAGMA synchronous=FULL";
      Hashtbl.add owners path ();
      {db; lock; path; closed = false}
    with error -> ignore (Sqlite3.db_close db); raise error
  with error -> Unix.close lock; raise error))
let check store = if store.closed then raise (Storage_error "Database is closed.")
let load store = protect (fun () ->
  check store;
  statement store.db "SELECT payload FROM snapshot WHERE id=1" (fun stmt ->
    match Sqlite3.step stmt with
    | Sqlite3.Rc.DONE -> None
    | Sqlite3.Rc.ROW -> (match Snapshot.decode (Sqlite3.column_text stmt 0) with
        | Ok snapshot -> Some snapshot | Error error -> raise (Storage_error error))
    | _ -> raise (Storage_error "Cannot load snapshot.")))
let save store snapshot ~events = protect (fun () ->
  check store;
  let payload = Snapshot.encode snapshot in
  (match Snapshot.decode payload with Ok _ -> () | Error error -> raise (Storage_error error));
  if List.length events > 1024 then raise (Storage_error "Too many events in one storage batch.");
  let event_payloads = List.map (fun event ->
    let payload = Events.encode event in
    if String.length payload > 65536 then raise (Storage_error "Event exceeds 64 KiB.");
    payload) events in
  exec store.db "BEGIN IMMEDIATE";
  try
    statement store.db "INSERT OR REPLACE INTO snapshot(id,payload) VALUES(1,?)" (fun stmt ->
      ensure (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT payload)); ensure (Sqlite3.step stmt));
    exec store.db "DELETE FROM runs";
    List.iter (fun (task : Model.task) -> List.iter (fun (run : Model.run_record) ->
      statement store.db "INSERT INTO runs(task_id,run_id,payload) VALUES(?,?,?)" (fun stmt ->
        ensure (Sqlite3.bind_values stmt [Sqlite3.Data.TEXT task.id; Sqlite3.Data.TEXT run.run_id;
          Sqlite3.Data.TEXT (Yojson.Basic.to_string (Snapshot.run_record run))]);
        ensure (Sqlite3.step stmt))) task.runs) snapshot.tasks;
    List.iter (fun payload -> statement store.db "INSERT INTO events(payload) VALUES(?)" (fun stmt ->
      ensure (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT payload)); ensure (Sqlite3.step stmt))) event_payloads;
    exec store.db "COMMIT"
  with error -> ignore (Sqlite3.exec store.db "ROLLBACK"); raise error)
let read_events store ~after ~limit = protect (fun () ->
  check store;
  if limit < 1 || limit > 1024 || after < 0L then raise (Storage_error "Invalid event page.");
  statement store.db "SELECT sequence,payload FROM events WHERE sequence>? ORDER BY sequence LIMIT ?" (fun stmt ->
    ensure (Sqlite3.bind_values stmt [Sqlite3.Data.INT after; Sqlite3.Data.INT (Int64.of_int limit)]);
    let rec loop rows = match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE -> List.rev rows
      | Sqlite3.Rc.ROW ->
          let event = match Events.decode (Sqlite3.column_text stmt 1) with
            | Ok event -> event | Error _ -> raise (Storage_error "Invalid stored event.") in
          loop ((Sqlite3.column_int64 stmt 0, event) :: rows)
      | _ -> raise (Storage_error "Cannot read events.") in
    loop []))
