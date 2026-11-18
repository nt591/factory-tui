type t = { name : string; source : string; description : string; revision : string }

val make :
  name:string ->
  source:string ->
  description:string ->
  revision:string ->
  (t, string) result
