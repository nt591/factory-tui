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

type job

val start : request -> job
val result : job -> (Model.task, string) result option
val close : job -> unit
