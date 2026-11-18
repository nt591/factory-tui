val vertical : columns:bool -> selected:string -> Model.task list -> Model.task list
val move : selected:string -> delta:int -> Model.task list -> string option
val horizontal : right:bool -> selected:string -> Model.task list -> string option
val edge : last:bool -> Model.task list -> string option
