val line : string -> string
(** Malformed UTF-8 becomes U+FFFD. C0/DEL/C1 controls become spaces. *)

val multiline : string -> string
(** LF line separators remain. All other replacements match [line], including CR. *)
