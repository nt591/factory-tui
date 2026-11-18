open Factory_tui

let checks = ref 0

let check name value =
  incr checks;
  if not value then failwith name

let ok = function Ok value -> value | Error error -> failwith error

let () =
  List.iter
    (fun name ->
      check "effort roundtrip"
        (Reasoning_effort.label (ok (Reasoning_effort.parse name)) = name))
    [ "low"; "medium"; "high" ];
  List.iter
    (fun name ->
      check "unrecognized effort refused" (Result.is_error (Reasoning_effort.parse name)))
    [ ""; "LOW"; " low"; "low\n"; "xhigh"; "none"; "secret" ];
  let directory = Unix.realpath (Filename.get_temp_dir_name ()) in
  List.iter
    (fun thread_id ->
      let original =
        ok
          (Codex.invocation ~executable:"/fixture/codex" ~directory ~model:"fixture"
             ~thread_id)
      in
      let configured = Codex.with_reasoning original Low in
      check "low effort encoded as literal configuration"
        (List.mem {|model_reasoning_effort="low"|} configured.arguments);
      check "stdin prompt marker remains last"
        (List.hd (List.rev configured.arguments) = "-");
      check "invocation head retains resume boundary"
        (match thread_id with
        | None -> List.hd configured.arguments = "exec"
        | Some _ ->
            List.filteri (fun i _ -> i < 2) configured.arguments = [ "exec"; "resume" ]))
    [ None; Some "thread" ];
  let config = ok (Live_runner.configure ~executable:"/bin/sh" ~gateway_file:None) in
  check "default preserves unspecified effort" (Live_runner.reasoning config = None);
  check "explicit setting stays on launch config"
    (Live_runner.reasoning (Live_runner.with_reasoning config Low) = Some Low);
  Printf.printf "Passed %d reasoning-effort checks. Pure invocation only.\n" !checks
