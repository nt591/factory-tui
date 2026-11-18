type action = Field of Workspace_form.field | Create | Cancel
type hit = { x : int; y : int; width : int; action : action }
type t = { image : Notty.image; hits : hit list }

val render :
  Workspace_form.t -> busy:bool -> status:string -> width:int -> height:int -> t
