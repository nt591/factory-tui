type mode = Existing | Folder | Greenfield

type t = {
  mode : mode;
  jj : string option;
  source : string option;
  parent : string option;
  revision : string option;
  model : string option;
}

val empty : t
