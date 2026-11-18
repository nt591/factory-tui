open Factory_tui
open Model

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let record =
  {
    run_id = "fixture";
    harness = Codex;
    model = "fixture";
    started_at = 100.;
    ended_at = None;
    status = Running;
    simulated = true;
    policy = Read_only;
  }

let () =
  check "active age uses supplied time"
    (Run_time.describe ~now:105.9 record = "run age 5s");
  check "age starts at zero" (Run_time.describe ~now:100. record = "run age 0s");
  check "minutes are readable" (Run_time.describe ~now:225. record = "run age 2m 5s");
  check "hours are readable" (Run_time.describe ~now:7405. record = "run age 2h 1m");
  List.iter
    (fun status ->
      let finished = { record with status; ended_at = Some 161.9 } in
      check "terminal time is frozen at recorded end"
        (Run_time.describe ~now:200. finished = "recorded duration 1m 1s"
        && Run_time.describe ~now:999999. finished = "recorded duration 1m 1s"))
    [ Completed; Stopped; Run_failed; Awaiting_input ];
  check "terminal record without end is not still running"
    (Run_time.describe ~now:200. { record with status = Completed } = "time unavailable");
  check "backwards clock does not imply negative or zero duration"
    (Run_time.describe ~now:99. record = "time unavailable");
  check "reversed recorded times are unavailable"
    (Run_time.describe ~now:200. { record with ended_at = Some 99. } = "time unavailable");
  List.iter
    (fun invalid ->
      check "nonfinite time is not rendered"
        (Run_time.describe ~now:invalid record = "time unavailable");
      check "nonfinite start is not rendered"
        (Run_time.describe ~now:200. { record with started_at = invalid }
        = "time unavailable"))
    [ Float.nan; Float.infinity; Float.neg_infinity ];
  check "extreme finite age cannot overflow integer conversion"
    (String.starts_with ~prefix:"run age "
       (Run_time.describe ~now:Float.max_float record));
  let saved = record in
  ignore (Run_time.describe ~now:123. record);
  check "duration formatting does not change run record" (record = saved);
  Printf.printf "Passed %d run time display checks. Supplied timestamps only.\n" !checks
