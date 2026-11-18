type t = { name : string; source : string; description : string; revision : string }

let make ~name ~source ~description ~revision =
  let controls value =
    String.exists (fun c -> Char.code c < 32 || Char.code c = 127) value
  in
  if
    name = ""
    || String.length name > 64
    || not
         (String.for_all
            (function
              | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' -> true | _ -> false)
            name)
  then
    Error
      "Project name must use letters, numbers, hyphens or underscores, up to 64 bytes."
  else if
    source = "" || Filename.is_relative source || controls source
    || String.length source > 4096
  then
    Error
      "Project repository must be an absolute path without controls, up to 4096 bytes."
  else if controls description || String.length description > 1024 then
    Error "Project description must be one line, up to 1024 bytes."
  else if
    String.trim revision = ""
    || revision.[0] = '-'
    || controls revision
    || String.length revision > 1024
  then Error "Project revision must be an explicit revision without controls."
  else Ok { name; source; description; revision }
