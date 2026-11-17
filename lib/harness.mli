type decoded = { event : Model.event option; raw : Yojson.Basic.t }

val decode : string -> (decoded, string) result
