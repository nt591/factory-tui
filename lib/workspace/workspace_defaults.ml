type t = {
  jj : string option;
  source : string option;
  parent : string option;
  revision : string option;
  model : string option;
}

let empty = { jj = None; source = None; parent = None; revision = None; model = None }
