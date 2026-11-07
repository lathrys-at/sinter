(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The test program of the book "Using Sinter". It reads a book folder, which
    holds [src/] and, when a page has starting files, [listings/], and it checks
    each page, each link, and each listing.

    A {e page} is a file under [src/] whose name ends in [.md], except
    [src/SUMMARY.md].

    {1 Fences}

    A fence is a line that starts with three or more backticks or tildes, as
    CommonMark says. The text after the mark is the label of the block. A block
    ends at a line of up to three spaces, the same mark at least as long as the
    opening one, and nothing else but spaces and tabs.

    An opening fence starts at the first column. A fence after spaces, after
    [>], or after a list marker fails the test. A fence with no closing fence
    fails the test, and so does an HTML comment with no end. Text inside an HTML
    comment is neither a block, nor a note, nor text.

    {1 Labels}

    - [console,run] and [console,run,exit=<n>], with [n] in decimal from 0 to
      255: a {e run block}. See "Run blocks".
    - [console,planned]: a {e planned block}. It does not run.
    - [<language>,file=<path>]: a {e file block}. It writes its text, byte for
      byte, to the path, relative to the root of the repository. Missing folders
      are made.
    - [<language>], or no label: a {e shown block}. Nothing reads its text,
      except that a line that starts with [$ ] fails the test.

    The name [console] counts in any case of letters. [console] with neither
    [run] nor [planned] fails the test. Any other label fails the test: a label
    with a space, a third part, a [file=] with no path, [run] or [planned] on
    another language, or an [exit] out of its range.

    A path of a file block fails the test when it is absolute, or when one of
    its parts is empty, [.], [..], or [.git] in any case of letters. It also
    fails when a part of the path, or the file itself, is a symbolic link in the
    repository.

    {1 Run blocks}

    Each line that starts with [$ ] is a command, and the lines below it, up to
    the next command, are its output. The first line of a run block must be a
    command, with text after the [$ ].

    A command fails the test when its first word is [cd] or [export], or when it
    only sets variables, such as [$ FOO=1]: the next command does not keep that
    state. A variable in front of a command, such as [$ FOO=1 sinter check], is
    allowed.

    Each command runs in its own [/bin/sh], in the root of the repository, as
    {!Fixture.shell} says, with an executable named [sinter] first on [PATH].
    The output of the command is its standard output and its standard error as
    one stream. The output must equal the lines below the command, byte for
    byte, each with its line feed. The last command of the block must exit with
    the [n] of the label, 0 by default. Each other command must exit with 0.
    Nothing in the output is masked.

    Outside a block, a line that starts with [$ ], after spaces and the marks of
    a list or a block quote, fails the test.

    {1 One repository for each page}

    The blocks of a page run in order in one new repository, as
    {!Fixture.with_new_repository} says. When the folder [listings/<stem>/]
    exists, where [<stem>] is the name of the page without its folder and
    without [.md], the one commit of the repository holds that folder. Without
    the folder, the repository has no commit.

    {1 Notes}

    A {e note} is exactly these two lines, with no other text in place of
    [<thing>], which is not empty, and with a blank line or the end of the file
    below them:

    {v
    > [!NOTE]
    > Sinter does not have this <thing> yet.
    v}

    Any other block quote that starts with [[!NOTE]], in any case of letters,
    fails the test. {e Text} is a line outside blocks, notes, and HTML comments
    that is not blank; a heading is text. The two rules:

    - A planned block must have a note above it, with only text between them.
      Another block between them, a planned block too, fails the test.
    - A run block with a note above it fails the test, unless text lies between
      them.

    {1 Links}

    A {e link} is a destination in an inline link or an image, the destination
    of a reference definition, or the value of an [href] or [src] attribute, in
    text and outside code spans. A footnote is not a link. The program reads the
    links of each page and of [src/SUMMARY.md], and it follows these rules. It
    reads no address outside the book.

    - A destination with a scheme, such as [https:], or that starts with [//],
      is an address outside the book. Nothing checks it.
    - An empty destination fails the test.
    - A destination that starts with [/], or that leads out of [src/], fails the
      test.
    - The rest of the destination, after percent decoding and up to the first
      [#], must name a file under [src/], with the same case of letters. An
      empty rest names the file of the link.
    - The text after the [#] must equal one of {!heading_ids} of that file, and
      that file must end in [.md].
    - A reference with a label, such as [[text][label]] or [[label][]], must
      have a definition in its file.

    Each page must be the target of a link in [src/SUMMARY.md]. *)

(** {1 Errors} *)

type problem =
  | Nested_fence  (** A fence is indented, or in a list or a block quote. *)
  | Unclosed_fence  (** A block has no closing fence. *)
  | Unclosed_comment  (** An HTML comment has no end. *)
  | Unknown_label of string  (** The label is not one of the known forms. *)
  | Console_without_label
      (** A [console] block says neither [run] nor [planned]. *)
  | Path_outside of string
      (** The path of a file block is not allowed, as "Labels" says. *)
  | No_command  (** A run block does not start with a command. *)
  | Command_outside_block
      (** A line that starts with [$ ] is not in a run block or a planned block.
      *)
  | Keeps_shell_state of string
      (** The command only changes the state of its own shell. *)
  | Bad_note  (** A note does not have the exact form. *)
  | Planned_without_note
      (** A planned block does not have a note above it, as "Notes" says. *)
  | Run_under_note
      (** A run block has a note above it, and no text lies between them. *)
  | Differs of { command : string; expected : string; actual : string }
      (** The output of the command differs from the lines of the block. *)
  | Wrong_exit of {
      command : string;
      expected : int;
      actual : int;
      output : string;
    }
      (** The command exited with a code other than the one it must give.
          [output] is what it wrote. *)
  | Cannot_promote of { command : string; output : string }
      (** The block cannot hold the output: it has no last line feed, or a line
          of it reads as a command or as the closing fence. *)
  | Harness of Fixture.error  (** A run, a process, or a file failed. *)
  | Empty_link  (** A link has an empty destination. *)
  | Rooted_link of string  (** A link starts with [/]. *)
  | Link_leaves_book of string  (** A link leads out of [src/]. *)
  | Missing_target of string  (** A link names no file under [src/]. *)
  | Missing_anchor of { target : string; anchor : string }
      (** The anchor names no heading of the file [target]. *)
  | Undefined_reference of string  (** A reference has no definition. *)
  | Not_in_summary  (** No link of [src/SUMMARY.md] names this page. *)
  | No_summary  (** The book has no file [src/SUMMARY.md]. *)
  | Listing_without_page
      (** A folder under [listings/] has the stem of no page, or an entry there
          is not a folder. *)
  | Listing_for_two_pages of string list
      (** Two or more pages, named here, have the stem of one listing. *)
  | Unreadable of string  (** A folder of the book cannot be read. *)

type error = {
  file : string;  (** The file or folder, by its path in the book folder. *)
  line : int option;  (** The line in that file, from 1, when one line is. *)
  problem : problem;
}
(** One failure of the book. *)

val message : error -> string
(** [message error] is the text that a failed test shows. It starts with the
    file and the line, and it says what is wrong. *)

(** {1 Modes} *)

type mode =
  | Compare  (** A difference in the output is an error. *)
  | Promote_into of string
      (** [Promote_into folder]: write the output of each run block into the
          copy of its page under [folder], which stands for [src/]. A wrong exit
          code stays an error. *)

val mode_of_environment :
  promote:string option -> source_root:string option -> (mode, string) result
(** [mode_of_environment ~promote ~source_root] reads the values of the
    variables [SINTER_PROMOTE] and [DUNE_SOURCEROOT]. It is
    [Promote_into (source_root ^ "/docs/book/src")] when [promote] is
    [Some "1"], and [Compare] for any other value of [promote]. It is [Error]
    with a message when [promote] is [Some "1"] and [source_root] is [None]. *)

(** {1 Checks} *)

val heading_ids : string -> string list
(** [heading_ids text] is the ids that mdBook 0.5.4 gives the headings of the
    Markdown [text], in order. It reads ATX headings and setext headings, also
    in a list or a block quote, and no line of a block or a comment. An id is
    the text of the heading without inline marks, with ASCII letters in lower
    case, each white space as [-], and only letters, digits, [_], and [-] kept.
    A second use of an id gets [-1], and so on. An entity counts as its
    character: [&amp;], [&lt;], [&gt;], [&quot;], [&apos;], and a numeric entity
    of printable ASCII or a space as that character, [&nbsp;] as a space, and
    any other entity as a byte above ASCII. An attribute [{#id}] gives the id as
    it stands, and it does not count as a use. Each byte above ASCII stays in
    the id, and a link with such a byte in its anchor fails the test. The result
    is empty when [text] breaks a rule of the fences or the comments. *)

val pages : string -> (string list, error) result
(** [pages book] is the paths of the pages of the book folder [book], relative
    to [src/], in sorted order. It is an [Unreadable] error when [src/] cannot
    be read. *)

val check_page : string -> (unit, int * problem) result
(** [check_page text] checks the fences, the labels, the notes, and the commands
    outside blocks of the page text [text], with no process and no file. The
    [Error] holds the line of the first problem, from 1, and the problem. It is
    total over all strings. *)

val check_links : string -> error list
(** [check_links book] is every failure of the rules of "Links" in the book
    folder [book], in the order of the files and their lines. It raises
    [Sys_error] when a file that it must read cannot be read. *)

val check_listings : string -> error list
(** [check_listings book] is an error for each entry of [listings/] that has no
    page, or more than one page, of its stem. An entry whose name starts with
    [.] does not count. The list is empty when the book has no [listings/]. *)

val run_page :
  ?bound:float ->
  ?caller:string array ->
  binary:string ->
  mode ->
  book:string ->
  string ->
  (string list, error) result
(** [run_page ~binary mode ~book page] checks the page as {!check_page} does,
    and then runs its blocks. [page] is a path of {!pages}. [binary] is the
    absolute path of the executable that a command starts by the name [sinter].
    [bound] is the time limit of each command, in seconds, and [caller] is the
    environment that each command starts from; {!Fixture.with_new_repository}
    and {!Fixture.shell} give their defaults. The run stops at the first error.

    In the mode [Compare], the result is the empty list. In the mode
    [Promote_into], the result is the path of the page that the run wrote, or
    the empty list when no output changed. A run that ends in an error writes
    nothing. The run writes into no other folder but the temporary folder.

    The commands run as they stand: a command can change any file that the user
    of the process can change. The rules of {!Fixture.run} on the working folder
    of the process hold here too. It raises [Invalid_argument] when [binary] is
    a relative path. *)

val tests :
  binary:string ->
  mode ->
  on_write:(string -> unit) ->
  string ->
  unit Alcotest.test_case list
(** [tests ~binary mode ~on_write book] is one test of {!check_links} and of the
    rule that [src/SUMMARY.md] exists, one test of {!check_listings}, and one
    test of {!run_page} for each page, named after the page. It calls [on_write]
    with each path that a promotion wrote. When [src/] cannot be read, the list
    holds one test that fails. *)
