open Model

type t = {
  tasks : task list;
  drafts : (string * string) list;
  selected : string;
  serial : int;
}

val encode : t -> string
val decode : string -> (t, string) result
val recover : t -> t
val run_record : Model.run_record -> Yojson.Basic.t
