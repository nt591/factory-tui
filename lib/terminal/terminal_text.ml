let sanitize ~newlines text =
  let buffer = Buffer.create (String.length text) in
  Uutf.String.fold_utf_8
    (fun () _ -> function
      | `Malformed _ -> Uutf.Buffer.add_utf_8 buffer Uutf.u_rep
      | `Uchar u ->
          let code = Uchar.to_int u in
          if code = 10 && newlines then Buffer.add_char buffer '\n'
          else if code < 32 || (code >= 127 && code <= 159) then
            Buffer.add_char buffer ' '
          else Uutf.Buffer.add_utf_8 buffer u)
    () text;
  Buffer.contents buffer

let line text = sanitize ~newlines:false text
let multiline text = sanitize ~newlines:true text
