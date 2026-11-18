type node = { mutable count : int; children : (string, node) Hashtbl.t }
type t = (string, string) Hashtbl.t

let node () = { count = 0; children = Hashtbl.create 4 }
let components path = String.split_on_char '/' path |> List.filter (( <> ) "")

let create repositories =
  let repositories = List.sort_uniq String.compare repositories in
  let root = node () in
  List.iter
    (fun repository ->
      let rec insert parent = function
        | [] -> ()
        | component :: rest ->
            let child =
              match Hashtbl.find_opt parent.children component with
              | Some child -> child
              | None ->
                  let child = node () in
                  Hashtbl.add parent.children component child;
                  child
            in
            child.count <- child.count + 1;
            insert child rest
      in
      insert root (List.rev (components repository)))
    repositories;
  let labels = Hashtbl.create (List.length repositories) in
  List.iter
    (fun repository ->
      let rec shortest parent suffix = function
        | [] -> repository
        | component :: rest ->
            let child = Hashtbl.find parent.children component in
            let suffix = component :: suffix in
            if child.count = 1 then String.concat "/" suffix
            else shortest child suffix rest
      in
      (* Display suffixes do not replace exact repository or workspace identities. *)
      Hashtbl.add labels repository (shortest root [] (List.rev (components repository))))
    repositories;
  labels

let label labels repository =
  Option.value ~default:repository (Hashtbl.find_opt labels repository)
