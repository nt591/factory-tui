type destination = Board | Archive

type item = {
  x : int;
  width : int;
  text : string;
  destination : destination;
  active : bool;
}

let make ~width ~archive ~count =
  let archive_label = Printf.sprintf "[ Archive · %d ]" count in
  let full_width = 12 + Notty.I.width (Notty.I.string Notty.A.empty archive_label) in
  let labels =
    if width >= full_width then [ ("[ Board ]", Board); (archive_label, Archive) ]
    else [ ("[Board]", Board); ("[Archive]", Archive) ]
  in
  let _, items =
    List.fold_left
      (fun (x, items) (text, destination) ->
        let cells = Notty.I.width (Notty.I.string Notty.A.empty text) in
        if x + cells > width then (x, items)
        else
          ( x + cells + 1,
            items
            @ [
                {
                  x;
                  width = cells;
                  text;
                  destination;
                  active =
                    (if archive then destination = Archive else destination = Board);
                };
              ] ))
      (1, []) labels
  in
  items

let extent items =
  List.fold_left (fun width item -> max width (item.x + item.width + 2)) 0 items
