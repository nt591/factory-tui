type mode = Existing | Folder | Greenfield

type t = {
  mode : mode;
  jj : string option;
  source : string option;
  parent : string option;
  revision : string option;
  model : string option;
}

let empty =
  {
    mode = Existing;
    jj = None;
    source = None;
    parent = None;
    revision = None;
    model = None;
  }
