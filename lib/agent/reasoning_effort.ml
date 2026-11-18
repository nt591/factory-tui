type t = Low | Medium | High

let parse = function
  | "low" -> Ok Low
  | "medium" -> Ok Medium
  | "high" -> Ok High
  | _ -> Error "Reasoning effort must be low, medium or high."

let label = function Low -> "low" | Medium -> "medium" | High -> "high"
