open Notty

let background = A.rgb_888 ~r:25 ~g:31 ~b:42
let key_background = A.rgb_888 ~r:52 ~g:68 ~b:82
let ink = A.rgb_888 ~r:218 ~g:227 ~b:237
let accent = A.rgb_888 ~r:118 ~g:190 ~b:218

let action label =
  let base = A.(fg ink ++ bg background) in
  let key = A.(fg accent ++ bg key_background ++ st bold) in
  if String.starts_with ~prefix:"[" label then
    match String.rindex_opt label '/' with
    | Some split ->
        let name = String.sub label 0 (split + 2) in
        let shortcut = String.sub label (split + 2) (String.length label - split - 2) in
        I.(string base (" " ^ name) <|> string key shortcut <|> string base " ")
    | None -> I.string base (" " ^ label ^ " ")
  else
    match String.index_opt label ' ' with
    | None -> I.string base (" " ^ label ^ " ")
    | Some split ->
        I.(
          string base " "
          <|> string key (String.sub label 0 split)
          <|> string base (String.sub label split (String.length label - split) ^ " "))

let hints ~width text =
  let separator = " · " in
  let rec split start index groups =
    if index + String.length separator > String.length text then
      List.rev (String.sub text start (String.length text - start) :: groups)
    else if String.sub text index (String.length separator) = separator then
      split
        (index + String.length separator)
        (index + String.length separator)
        (String.sub text start (index - start) :: groups)
    else split start (index + 1) groups
  in
  let groups = split 0 0 [] in
  let base = A.(fg ink ++ bg background) in
  let key = A.(fg accent ++ bg background ++ st bold) in
  let segment group =
    match String.index_opt group ':' with
    | Some split ->
        I.(
          string key (String.sub group 0 (split + 1))
          <|> string base (String.sub group (split + 1) (String.length group - split - 1)))
    | None -> I.string base group
  in
  I.hcat
    (List.mapi
       (fun index group ->
         if index = 0 then segment group else I.(string base " · " <|> segment group))
       groups)
  |> I.hsnap ~align:`Left width
