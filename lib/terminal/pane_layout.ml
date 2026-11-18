type layout = Board | Detail | Stacked of int | Side_by_side of int
type result = Changed | At_limit | No_split
type split = { total : int; first : int; minimum : int; maximum : int; vertical : bool }

type t = {
  mutable height_share : int option;
  mutable width_share : int option;
  mutable current : split option;
}

let create () = { height_share = None; width_share = None; current = None }
let hide t = t.current <- None

let reset t =
  t.height_share <- None;
  t.width_share <- None

let split preferences ~total ~default ~minimum ~maximum ~vertical =
  let share =
    Option.bind preferences (fun t -> if vertical then t.width_share else t.height_share)
  in
  let desired =
    match share with None -> default | Some share -> ((total * share) + 5000) / 10000
  in
  let first = max minimum (min maximum desired) in
  Option.iter
    (fun t -> t.current <- Some { total; first; minimum; maximum; vertical })
    preferences;
  first

(* A short body cannot show both panes without hiding the reply editor. *)
let choose ?preferences ~width ~height ~detail_focused () =
  Option.iter hide preferences;
  if width >= 155 then
    Side_by_side
      (split preferences ~total:width
         ~default:(max 88 (width * 58 / 100))
         ~minimum:88 ~maximum:(width - 64) ~vertical:true)
  else if detail_focused && height < 21 then Detail
  else if height >= 17 then
    Stacked
      (split preferences ~total:height
         ~default:(max (if height >= 27 then 16 else 9) (height * 52 / 100))
         ~minimum:9
         ~maximum:(height - if height >= 21 then 10 else 8)
         ~vertical:false)
  else Board

let resize t ~detail ~delta =
  match t.current with
  | None -> No_split
  | Some current ->
      let delta = max (-current.total) (min current.total delta) in
      let delta = if detail then -delta else delta in
      let first = max current.minimum (min current.maximum (current.first + delta)) in
      if first = current.first then At_limit
      else
        let share = ((first * 10000) + (current.total / 2)) / current.total in
        if current.vertical then t.width_share <- Some share
        else t.height_share <- Some share;
        t.current <- Some { current with first };
        Changed
