(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(* @cites ledger-layout *)

(** The ledger: the entries of the ref [refs/sinter/ledger], the checks of each
    line and of the tree that holds the lines, and the verification of the
    history of the ref. *)

val ref_name : string
(** The full name of the ledger ref: ["refs/sinter/ledger"]. *)

val version : int
(** The version of the entries that this module reads: [1]. *)

val chunk_size : int
(** The number of entries of a full chunk: [50]. *)

val set_limit : int
(** The longest canonical bytes, [1_048_576], that the hash of the set of a
    [commitment-set] entry may cover: {!Commitment_set.bytes} of its plan scope
    and its steps. *)

(** {1 Entries} *)

(** What an approval approves. *)
type approved =
  | Text of { rev : int; xh : string }
      (** a declaration, at the revision [rev] and the extent hash [xh] *)
  | Commitment of string
      (** a plan or a step, at the commitment-set hash or the step hash *)

type scope = {
  step : string option;
      (** the slug of the step whose own scope holds the glob; [None] for a glob
          of the plan scope *)
  glob : string;
}
(** One glob of a scope of a commitment set. *)

type promise = { step : string; word : string; target : string }
(** One promise of a commitment set: the slug of its step, its tag word, and its
    tag target. *)

(** The fields of an entry that its kind gives. *)
type body =
  | Approval of { subject : string; approved : approved; note : string option }
  | Commitment_set of {
      csh : string;
      scopes : scope list;  (** in the order of the line *)
      promises : promise list;  (** in the order of the line *)
      csh_holds : bool;
          (** [csh] is the commitment-set hash of [scopes] and [promises], as
              {!Commitment_set.hash} computes it from the plan scope, the
              effective scope of each step, and the promises, and the bytes that
              the hash covers are no longer than {!set_limit}. The reader
              computes their length first, with {!Commitment_set.size}, and
              computes no hash past the limit. A set whose hash does not hold is
              still an entry; the ledger is not broken. *)
    }
  | Decline of { subject : string; hash : string; reason : string }
  | Delivered of { subject : string; csh : string; merge : string }
  | Completed of {
      subject : string;
      approval : string option;
      merge : string;
      report : string;
    }
  | Abandoned of { subject : string; reason : string }
  | Void of { dropped : string; reason : string }
      (** the place of the entry [dropped], which a repair dropped *)

type entry = private {
  id : string;  (** [e-] and 12 lowercase hexadecimal digits *)
  v : int;
  seq : int;
      (** the place of the entry in the order of the ledger, 1 or more *)
  by : string;
  ts : string;  (** [YYYY-MM-DDTHH:MM:SSZ] *)
  head : string;  (** an object id *)
  branch : string option;
  tool : string;
  body : body;
  line : string;  (** the line of the entry, without its line feed *)
}
(** One entry of a known kind, as its line gives it. *)

val kind_name : body -> string
(** [kind_name body] is the name of the kind of [body], as the field [kind]
    writes it, for example ["commitment-set"]. *)

val subject : body -> string option
(** [subject body] is the field [subject] of [body]; [None] for the kinds
    [commitment-set] and [void], which have none. *)

val compare : entry -> entry -> int
(** [compare a b] orders two entries by their [seq]. *)

(** {1 Lines} *)

(** Why a line fails the checks of a line. *)
type line_fault =
  | Not_json  (** the line is not a JSON value *)
  | Not_an_object  (** the line is a JSON value that is not an object *)
  | Bad_value of string
      (** the value of this field is of a shape that a line does not allow: a
          float, a null, an integer outside [-(2^53-1)] to [2^53-1], an object,
          an array of arrays, an array of objects that are not flat, or an array
          of scalars of more than one type *)
  | Repeated_key of string  (** the object holds this key twice *)
  | Not_utf_8  (** a string or a key is not valid UTF-8 *)
  | Not_canonical
      (** the line is not the canonical form of its value: the bytes differ *)
  | Missing_field of string  (** a required field is absent *)
  | Wrong_type of string  (** the value of this field is not of its type *)
  | Wrong_id of string
      (** [id] is not the id of the line; the string is the id that the line has
      *)
  | Approval_hashes
      (** an approval holds both [rev] and [csh], or neither [xh] nor [csh], or
          [rev] without [xh] *)

(** What one line gives. *)
type read =
  | Known of { entry : entry; unknown_fields : int }
      (** an entry of a known kind, and the number of its fields that its kind
          does not name *)
  | Unknown of { id : string; kind : string; seq : int }
      (** an entry of a kind that this module does not know *)

(** Why a line gives no entry. *)
type line_error =
  | Too_new of int
      (** the line is a JSON object whose [v] is this integer, which is above
          {!version} *)
  | Fault of { id : string option; fault : line_fault }
      (** the line fails a check. [id] is the field [id] of the line when the
          line is a JSON object whose [id] is a string. *)

val read_line : Git.object_format -> string -> (read, line_error) result
(** [read_line format line] reads one line of a chunk, without its line feed, in
    a repository of [format]. It reads [v] first: a line that is a JSON object
    with an integer [v] above {!version} is [Too_new]. Then the line must be in
    the canonical form, hold the fields [id] and [kind], each a string, and [v]
    and [seq], each an integer of 1 or more, and have the id of its bytes: [e-]
    and the first 12 hexadecimal digits of the SHA-256 of the canonical form of
    its value without [id]. A line of a known kind must also hold each field of
    its kind, each of its type; a commit is an object id of the length of
    [format]; each object of [scopes] holds a string [glob] and may hold a
    string [step], and each object of [promises] holds the strings [step],
    [word], and [target]. A key of such an object that it does not name counts
    as an unknown field.

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val id_of : Json.t -> (string, Json.error) result
(** [id_of value] is the id that a line of [value] has: [e-] and the first 12
    hexadecimal digits of the SHA-256 of the canonical form of [value] without
    its member [id]. The error is the error of {!Json.to_string}.

    @raise Invalid_argument if [value] is not an [Object].
    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

(** {1 The ledger of a repository} *)

(** Why a ledger is broken. *)
type fault =
  | Not_a_commit of Git.Decode.kind
      (** the ref names an object of this type, which is not a commit *)
  | Bad_commit of string  (** the commit object does not decode *)
  | Merge_commit of int  (** the commit has this number of parents, 2 or more *)
  | Parent_not_a_commit of { parent : string; kind : Git.Decode.kind }
      (** a parent of the commit is an object of another type *)
  | Bad_tree of string
      (** the tree object at the path, or of the commit when the path is [None],
          does not decode *)
  | Wrong_object of Git.Decode.kind
      (** the object at the path is of this type: a folder that is no tree, or a
          chunk that is no blob *)
  | Wrong_path of { mode : int }
      (** the tree holds the path with this mode, and a ledger holds no such
          path *)
  | Unordered_tree
      (** the names of the tree at the path, or of the commit when the path is
          [None], are not in increasing byte order: a name comes twice, or after
          a greater name *)
  | Empty_folder  (** the folder at the path holds no entry *)
  | Empty_chunk  (** the chunk at the path holds no byte *)
  | No_line_feed  (** the last line of the chunk at the path has no line feed *)
  | Wrong_name of string
      (** the chunk at the path does not have the name of the id of its first
          entry, this string *)
  | Bad_line of line_fault  (** the line fails a check *)
  | Repeated_id  (** the id of the line is the id of an earlier line *)
  | Repeated_seq of int
      (** the [seq] of the line, this integer, is the [seq] of an earlier line
      *)
  | Missing_seq of { seq : int; count : int }
      (** the tree of the commit holds [count] entries, and no entry with the
          [seq] [seq], which is the least [seq] from 1 to [count] that the tree
          lacks *)
  | Dropped of { parent : string }
      (** the parent holds the entry at the path and the line, and the commit
          holds no line of the same bytes *)

type broken = {
  commit : string;
      (** the object id of the commit that holds the fault, or of the object
          that the ref names when it names no commit *)
  path : string option;  (** the path of the fault in a tree *)
  line : int option;  (** the line of the fault in the chunk at [path] *)
  entry : string option;  (** the id of the entry at fault *)
  fault : fault;
}
(** The first fault of a broken ledger. For [Dropped], [path] and [line] are the
    place of the entry in the parent. *)

(** Why the ledger does not read. *)
type error =
  | Repository of Git.error  (** git fails *)
  | Broken of broken  (** the ledger is broken *)
  | Newer of { commit : string; path : string; line : int; version : int }
      (** the line at [path] and [line] of [commit] has the version [version],
          above {!version} *)
  | Missing_parent of { commit : string; parent : string }
      (** the clone does not hold the parent [parent] of [commit], as in a
          shallow clone *)
  | Missing_object of { commit : string; id : string }
      (** the clone does not hold the object [id] of the tree of [commit], as in
          a partial clone *)

val explain : error -> Error_text.t
(** [explain error] says what is wrong and what to do, for the person who runs
    the tool. A path prints as {!Display.clean} gives it. The help of [Broken]
    names [sinter ledger repair]; the help of [Newer] says to upgrade sinter;
    the help of [Missing_parent] and [Missing_object] gives a git command that
    fetches the ledger. *)

type t
(** The entries of the tip of a ledger, as {!read} reads them. *)

(** How much of the ledger {!read} checks. *)
type depth =
  | Tip  (** the tip: the ref, its tree, and every line of every chunk *)
  | History
      (** the tip, and each commit of the history with its parent, from the tip
          back to the first commit *)

val read : Git.t -> depth -> (t option, error) result
(** [read repo depth] reads the ledger of [repo] and checks it to [depth], with
    one [git for-each-ref] and one [git cat-file --batch]. It is [None] when
    [repo] has no ref {!ref_name}. A ref whose object [repo] does not hold gives
    [Missing_object].

    The entries of the tip must hold each [seq] from 1 to their number once: a
    [seq] that an earlier line holds is [Repeated_seq] at its line, and a [seq]
    that no line holds is [Missing_seq] after the last chunk. At [History], each
    parent must hold each [seq] from 1 to the number of its entries; the read
    finds this from the lines of the child that no line of the parent matches,
    which must each have a [seq] above that number, and gives [Missing_seq] of
    the parent after the other checks of the parent.

    A chunk at one path with one object id in a commit and its parent is read
    once. The parents of a commit are those of its raw object: the grafts and
    the replacement refs of [repo] do not count. The error is the first fault in
    the order of the walk: the tip, then each parent from the tip back; in each
    commit, the tree, the folder [entries], each folder in the byte order of the
    names, and each chunk of a folder in the byte order of the names, each line
    in order.

    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val tip : t -> string
(** [tip ledger] is the object id of the commit at the ref. *)

val entries : t -> entry list
(** [entries ledger] is each entry of a known kind of the tip, in the order of
    {!compare}. *)

val commits : t -> int
(** [commits ledger] is the number of commits that {!read} checked: [1] at
    [Tip], and the number of commits of the history at [History]. *)

type work = {
  waits : int;
      (** the number of times that the read wrote ids to git and waited for the
          answers, as {!Git.waits} counts them *)
  listings : int;
      (** the number of listings of the folder [entries] that the read decoded
          in full, with the checks of their paths *)
  lines : int;  (** the number of lines that the read checked by {!read_line} *)
  matches : int;
      (** the number of lines of a parent that the read looked up by their bytes
          in the lines of the child *)
}
(** The work of one {!read}. *)

val work : t -> work
(** [work ledger] is the work of the {!read} that gave [ledger]. For one ledger
    and one depth, it is the same on every read. *)

val unknown : t -> int * int
(** [unknown ledger] is the number of entries of an unknown kind, and the number
    of fields of the entries of a known kind that their kind does not name, in
    the tip. *)

val warning : t -> string option
(** [warning ledger] is the text of the warning about the entries and the fields
    that {!unknown} counts, for example
    [the ledger holds 3 entries of an unknown kind and 1 unknown field; sinter
     ignores them]. Each part with a count of 0 is left out. It is [None] when
    both counts are 0. *)

(** {1 Output} *)

val finding : broken -> Finding.t
(** [finding broken] is the finding of the class [ledger-broken] about the
    commit of [broken]: its subject is [ledger:<commit>], it has no place, and
    its detail says what is at fault and where, as the fault of {!explain} says
    it after [the ledger is broken: ]. *)

val summary : t -> string
(** [summary ledger] is one line for the person who runs the tool, for a ledger
    whose check passed:
    [the ledger passes verification: <n> entries in <c> commits], where [<n>]
    counts the entries of the tip of every kind and [<c>] is {!commits}, with
    [1 entry] and [1 commit] for a count of 1. *)

val log_line : entry -> string
(** [log_line entry] is the line of [entry] in the text form of
    [sinter ledger log], without a line feed: its [seq], its [ts], its [id], its
    kind, its subject, and its [by], separated by a space. A [commitment-set]
    has its [csh], and a [void] the id of the entry that it dropped, in place of
    a subject. Each text of the entry prints as {!Display.clean} gives it. *)
