(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Version 1 of the porcelain form of the findings of a check: one line of nine
    fields for each finding, and header lines. Each function appends bytes to a
    buffer. *)

val version : int
(** The version of the form, [1]. *)

(** {1 Headers} *)

(** A header that [--headers] can name. *)
type header =
  | Base  (** the base commit *)
  | Ledger  (** the commit at the ledger ref *)
  | Gate  (** the gate of the check *)
  | Mode  (** the mode of the run *)
  | Tool  (** the version of the tool *)

val headers : header list
(** Every header, in the order of the output: [Base], [Ledger], [Gate], [Mode],
    and [Tool]. *)

val header_name : header -> string
(** [header_name header] is the name of [header]: ["base"], ["ledger"],
    ["gate"], ["mode"], or ["tool"]. *)

val header_of_name : string -> header option
(** [header_of_name name] is the header whose {!header_name} is [name], or
    [None]. *)

(** Which header lines the output holds. *)
type header_lines =
  | No_headers  (** no header line *)
  | Headers of header list
      (** the line [# porcelain 1], then one line for each header of the list,
          once each, in the order of {!headers} *)

val add_header : Buffer.t -> nul:bool -> string -> string -> unit
(** [add_header buffer ~nul name value] appends the header line [# ], [name], a
    space, and [value], and then a line feed, or a NUL byte when [nul] is
    [true].

    @raise Invalid_argument
      if [name] or [value] is empty, or holds a space, a byte below 0x20, the
      byte 0x7F, a double quote, or a backslash. *)

(** {1 Findings} *)

val add_field : Buffer.t -> string -> unit
(** [add_field buffer field] appends [field] as a field of a line. A field that
    holds no byte below 0x20, no byte 0x7F, no double quote, and no backslash is
    appended as it is. Any other field is appended in double quotes, with each
    of those bytes written as an escape: a backslash before a double quote or a
    backslash; [\a], [\b], [\t], [\n], [\v], [\f], and [\r] for the bytes 0x07
    to 0x0D; and a backslash and three octal digits for every other byte below
    0x20 and for 0x7F. Every other byte is appended as it is. The result holds
    no tab and no line feed. *)

val add_finding :
  Buffer.t -> nul:bool -> tier:Finding_class.tier option -> Finding.t -> unit
(** [add_finding buffer ~nul ~tier finding] appends the line of [finding]: its
    nine fields, in this order:

    + the {!Finding_class.tier_name} of [tier], or [none] when [tier] is [None];
    + the {!Finding_class.name} of its class;
    + the path of its place;
    + the line and the column where its place starts;
    + the line and the column where its place stops, the column exclusive;
    + the {!Finding.subject_id} of its subject;
    + its detail.

    A number is written in decimal, with no leading zero. A finding with no
    place has five empty fields from the path to the stop column; a finding with
    no detail has an empty last field.

    When [nul] is [false], each field is written as {!add_field} writes it, a
    tab stands between two fields, and a line feed ends the line. When [nul] is
    [true], a field that holds a NUL byte or starts with a double quote is
    written as {!add_field} writes it, every other field is written as it is,
    and a NUL byte ends each field, the last field included. *)
