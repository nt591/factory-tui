open Factory_tui

let checks = ref 0

let check name condition =
  incr checks;
  if not condition then failwith name

let file document line = Option.get (Diff_document.file_at document ~line)

let () =
  let empty = Diff_document.parse "" in
  check "empty patch has no lines or files"
    (Diff_document.line_count empty = 0 && Diff_document.file_count empty = 0);
  check "empty patch has no navigation target"
    (Diff_document.next_file empty ~line:0 = None
    && Diff_document.previous_file empty ~line:0 = None);
  let patch =
    "preamble\n\
     diff --git a/added file.txt b/added file.txt\n\
     new file mode 100644\n\
     --- /dev/null\n\
     +++ b/added file.txt\n\
     @@ -0,0 +1,3 @@\n\
     +first\n\
     +diff --git a/fake b/fake\n\
     +++ b/fake\n\
     diff --git a/deleted.txt b/deleted.txt\n\
     deleted file mode 100644\n\
     --- a/deleted.txt\n\
     +++ /dev/null\n\
     @@ -1 +0,0 @@\n\
     -deleted\n\
     diff --git a/before.txt b/after.txt\n\
     similarity index 100%\n\
     rename from before.txt\n\
     rename to after.txt\n\
     diff --git a/image.png b/image.png\n\
     Binary files a/image.png and b/image.png differ\n\
     diff --git a/\"quoted\" b/\"quoted\"\n\
     --- \"a/quoted\\tname\"\n\
     +++ \"b/quoted\\tname\"\n\
     @@ -1 +1 @@\n\
     -old\n\
     +new\n"
  in
  let document = Diff_document.parse patch in
  check "only file headers count as files" (Diff_document.file_count document = 5);
  check "preamble has no current file" (Diff_document.file_at document ~line:0 = None);
  check "added filename preserves spaces" ((file document 1).name = "added file.txt");
  check "added content cannot replace file name"
    ((file document 8).name = "added file.txt");
  check "deleted filename uses old-side header" ((file document 9).name = "deleted.txt");
  check "rename without hunks uses new name" ((file document 15).name = "after.txt");
  check "binary file retains opaque header label"
    ((file document 19).name = "a/image.png b/image.png");
  check "quoted filenames remain opaque" ((file document 21).name = "\"b/quoted\\tname\"");
  check "current file indexes are zero-based" ((file document 15).index = 2);
  check "next file from preamble selects first header"
    ((Option.get (Diff_document.next_file document ~line:0)).line = 1);
  check "next file from body selects the following header"
    ((Option.get (Diff_document.next_file document ~line:7)).line = 9);
  check "previous file from body selects previous file"
    ((Option.get (Diff_document.previous_file document ~line:14)).line = 1);
  check "previous from first file has no target"
    (Diff_document.previous_file document ~line:8 = None);
  check "next from last file has no target"
    (Diff_document.next_file document ~line:26 = None);
  check "out-of-range line after patch stays in last file"
    ((file document max_int).index = 4);
  check "negative line has no current file"
    (Diff_document.file_at document ~line:(-1) = None);
  check "bounded line slices preserve exact text"
    (Diff_document.lines document ~start:5 ~count:4
    = [ "@@ -0,0 +1,3 @@"; "+first"; "+diff --git a/fake b/fake"; "+++ b/fake" ]);
  check "slice clamps negative start and oversized count"
    (List.length (Diff_document.lines document ~start:(-9) ~count:max_int)
    = Diff_document.line_count document);
  check "line fold preserves all stored text"
    (Diff_document.fold_lines document ~init:[] ~f:(fun lines text -> text :: lines)
    |> List.rev
    = Diff_document.lines document ~start:0 ~count:max_int);
  check "slice beyond end is empty"
    (Diff_document.lines document ~start:max_int ~count:2 = []);
  check "negative slice count is empty"
    (Diff_document.lines document ~start:0 ~count:(-1) = []);
  let opaque = Diff_document.parse "a patch without Git headers\n+addition" in
  check "unknown patch still retains lines"
    (Diff_document.line_count opaque = 2 && Diff_document.file_count opaque = 0);
  let large =
    List.init 2000 (fun index -> Printf.sprintf "diff --git a/%d b/%d\n+body" index index)
    |> String.concat "\n" |> Diff_document.parse
  in
  check "large file index locates the final file"
    (Diff_document.file_count large = 2000 && (file large 3999).index = 1999);
  check "large file index advances a middle file"
    ((Option.get (Diff_document.next_file large ~line:1998)).index = 1000);
  Printf.printf "Passed %d diff document checks. Pure patch text only.\n" !checks
