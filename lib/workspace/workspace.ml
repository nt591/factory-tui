type t = { source : string; destination : string; base : string; name : string }

let source t = t.source
let destination t = t.destination
let base t = t.base
let name t = t.name

exception Workspace_error of string

let unwrap = function Ok value -> value | Error error -> raise (Workspace_error error)

let path value =
  if
    Filename.is_relative value
    || String.exists (fun c -> Char.code c < 32 || Char.code c = 127) value
  then
    raise (Workspace_error "Workspace paths must be absolute without control characters.")

let inside parent child =
  child = parent || String.starts_with ~prefix:(parent ^ "/") child

let commit id = String.length id = 40 || String.length id = 64

let command ~jj ~source args =
  let output =
    unwrap
      (Command.run ~executable:jj
         ~arguments:([ "--no-pager"; "--color"; "never"; "--repository"; source ] @ args)
         ~directory:source ~timeout:15. ~max_output:2097152)
  in
  if output.status <> Unix.WEXITED 0 then
    raise
      (Workspace_error
         "jj command failed. Output was not printed; retain any partial workspace for \
          inspection.");
  output.stdout

let create ~jj ~source ~destination ~revision =
  try
    path jj;
    path source;
    path destination;
    if
      String.trim revision = ""
      || revision.[0] = '-'
      || String.length revision > 1024
      || String.exists (fun c -> Char.code c < 32 || Char.code c = 127) revision
    then raise (Workspace_error "Workspace creation requires an explicit valid revision.");
    let source = Unix.realpath source in
    if
      (not (Sys.is_directory source))
      || not (Sys.file_exists (Filename.concat source ".jj"))
    then
      raise
        (Workspace_error
           "Source must be a jj checkout. Git-only conversion is not automatic.");
    let parent = Unix.realpath (Filename.dirname destination) in
    let leaf = Filename.basename destination in
    if leaf = "." || leaf = ".." || leaf = "/" then
      raise (Workspace_error "Invalid workspace destination.");
    let destination = Filename.concat parent leaf in
    if inside source destination || inside destination source then
      raise (Workspace_error "Workspace destination must be outside the source checkout.");
    (try
       ignore (Unix.lstat destination);
       raise (Workspace_error "Workspace destination already exists.")
     with Unix.Unix_error (Unix.ENOENT, _, _) -> ());
    let ids =
      command ~jj ~source
        [
          "--ignore-working-copy";
          "log";
          "--no-graph";
          "--revisions";
          revision;
          "--template";
          {|commit_id ++ "\n"|};
        ]
      |> String.split_on_char '\n'
      |> List.filter (fun id -> id <> "")
    in
    let base =
      match ids with
      | [ id ]
        when commit id
             && String.for_all
                  (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
                  id ->
          id
      | _ -> raise (Workspace_error "Base revision must resolve to exactly one commit.")
    in
    let name = "factory-" ^ leaf in
    if String.length name > 200 then
      raise (Workspace_error "Workspace destination name is too long.");
    ignore
      (command ~jj ~source
         [ "workspace"; "add"; "--name"; name; "--revision"; base; destination ]);
    Ok { source; destination; base; name }
  with
  | Workspace_error error -> Error error
  | Unix.Unix_error _ | Sys_error _ ->
      Error "Cannot inspect workspace paths. Parents must already exist."

let diff ~jj workspace =
  try
    Ok
      (command ~jj ~source:workspace.destination
         [ "diff"; "--from"; workspace.base; "--to"; "@"; "--git" ])
  with
  | Workspace_error error -> Error error
  | Unix.Unix_error _ | Sys_error _ -> Error "Cannot read workspace changes."

let reference t : Model.workspace_ref =
  { source = t.source; directory = t.destination; base = t.base; name = t.name }

let restore (reference : Model.workspace_ref) =
  let task = Model.make ~id:"workspace-validation" ~title:"" ~repository:"" in
  match Model.attach_workspace task reference with
  | Error error -> Error error
  | Ok _ ->
      Ok
        {
          source = reference.source;
          destination = reference.directory;
          base = reference.base;
          name = reference.name;
        }
