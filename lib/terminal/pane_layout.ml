type t = Board | Detail | Stacked of int | Side_by_side of int

(* A short body cannot show both panes without hiding the reply editor. *)
let choose ~width ~height ~detail_focused =
  if width >= 155 then Side_by_side (max 88 (width * 58 / 100))
  else if detail_focused && height < 21 then Detail
  else if height >= 17 then
    Stacked (max (if height >= 27 then 16 else 9) (height * 52 / 100))
  else Board
