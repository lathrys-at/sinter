(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** A generated tree of markdown files for the benchmark, made from a seed.

    A tree of [n] declarations holds:

    - requirements: [n * 5 / 10] sections of [@req], 25 to a file under
      [spec/reqs/]; a tenth of them also [@refines] an earlier requirement
    - designs: [n * 3 / 10] sections of [@design], 25 to a file under
      [docs/design/], each with one or two [@satisfies] of a requirement; about
      3 in 10 pin [v1], and about 1 in 100 name a slug that no file declares
    - decisions: the rest of the [n], one to a file under [docs/decisions/],
      each with up to two [@cites] of an earlier decision and at times a
      [@cites] of an external id [gh/<id>]; each decision from the third on
      whose number is 1 or 2 above a multiple of 30 [@supersedes] the decision
      before it; each decision whose number is 7, 17, or 27 above a multiple of
      50 carries [@deprecated], [@rejected], or [@deferred]: a retired decision
    - notes: sections under [docs/notes/] that [@cites] a requirement and
      declare nothing
    - acks: [n / 20] sections under [docs/acks/], 25 to a file, when the tree
      has a retired decision. Each [@cites] a retired decision. About a quarter
      carry an [@ack retired] of the citation whose hash is the first 8 digits
      of the hash of their block; a quarter carry one whose first digit differs;
      a quarter carry both, the wrong one first; and a quarter carry none
    - plans: one plan for each 1,000 declarations, and at least one, under
      [.plans/]; each has 20 steps with a [@scope], and each step but the last
      makes two to four promises
    - [README.md], and the manifest [sinter.toml], which reads every markdown
      file and declares the namespace [gh]

    Every count and every text comes from the seed alone, through
    [Random.State], so one seed and one [n] give the same tree on every run of
    one build. *)

type t
(** A generated tree. *)

val make : seed:int -> declarations:int -> t
(** [make ~seed ~declarations] is the tree of [declarations] declarations for
    [seed]. It parses the files of the acks with the markdown pack, to read the
    hashes of their blocks.

    @raise Invalid_argument if [declarations] is below 2.
    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val main : t -> (string * string) list
(** [main tree] is every file of the commit on the branch [main], by its path
    and its content, in the byte order of the paths. *)

val work : t -> (string * string) list
(** [work tree] is each file that the commit on the branch [work] changes, by
    its path and its new content, in the byte order of the paths. It holds one
    file in 100 of {!main}, and at least one; [sinter.toml] is never one of
    them. *)

val uncommitted : t -> (string * string) list
(** [uncommitted tree] is each file whose content in the working tree differs
    from the branch [work], by its path and its content in the working tree, in
    the byte order of the paths. It holds one file in 1,000 of {!main}, and at
    least one; [sinter.toml] is never one of them. *)

val count : t -> string -> int
(** [count tree kind] is the number of declarations of [kind] in {!main}: of
    [req], [design], or [decision]; and the number of plans for [plan]. It is
    [0] for any other word. *)

val write : t -> string -> Git_fixture.t
(** [write tree dir] makes the repository of [tree] in [dir], as
    {!Git_fixture.init_in} does: the working tree is [dir/repo]. The branch
    [main] holds one commit with the files of {!main}. The branch [work] holds
    one more commit, with the changes of {!work}. [HEAD] is [work]. The working
    tree holds the content of {!uncommitted}. Every file of the working tree has
    the modification time 1700000000, and the index holds the stat data of each
    file whose content it holds, so git reads no file whose stat data match the
    index.

    @raise Invalid_argument as {!Git_fixture.init_in} raises it.
    @raise Failure when git fails, with the standard error of git. *)
