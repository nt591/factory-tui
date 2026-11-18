val next : prefix:string -> serial:int -> Model.task list -> string * int
(** Return an unused ID and its counter. Retained output namespaces are reserved too. *)
