type t = { needle : string; fallback : int array }

let prepare query =
  let needle = String.lowercase_ascii query in
  let fallback = Array.make (String.length needle) 0 in
  let matched = ref 0 in
  for index = 1 to String.length needle - 1 do
    while !matched > 0 && needle.[!matched] <> needle.[index] do
      matched := fallback.(!matched - 1)
    done;
    if needle.[!matched] = needle.[index] then incr matched;
    fallback.(index) <- !matched
  done;
  { needle; fallback }

let contains t text =
  let length = String.length t.needle in
  if length = 0 then true
  else
    let matched = ref 0 and index = ref 0 in
    (* Fallback reuses the matched prefix instead of rescanning repeated text. *)
    while !index < String.length text && !matched < length do
      let char = Char.lowercase_ascii text.[!index] in
      while !matched > 0 && t.needle.[!matched] <> char do
        matched := t.fallback.(!matched - 1)
      done;
      if t.needle.[!matched] = char then incr matched;
      incr index
    done;
    !matched = length
