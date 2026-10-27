(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The reader of the built-in pack [markdown]. It parses a markdown file with
    the embedded grammar, and gives the structure that the facts of the file
    come from: the sections, the tag lines and their blocks, the extents of the
    declarations and their hashes, the paragraphs whose tags it does not read,
    and the places of the parse failures.

    A line and a column count from 1. A column counts characters (Unicode code
    points). A line ends at a line feed (LF), and a carriage return (CR) right
    before an LF is part of the line ending. A byte order mark at the start of
    the file is part of no line and counts in no column.

    A section opens at an ATX heading that no block quote and no list item
    holds; the text before the first such heading is the section of level 0. The
    tag-bearing nodes are the first paragraph of a section and the first
    paragraph of a list item, when no block quote holds them. A declaration is a
    tag line of the word [req], [design], [decision], or [rule] whose target
    matches the slug pattern. *)

type position = Line_index.position = { line : int; column : int }

type span = { start : position; stop : position }
(** A piece of the file. [start] is the place of its first character. [stop] is
    on the line of its last character, one column past that character. A span
    never ends on a line ending. A span of no character has [stop = start]. *)

(** {1 The reader} *)

type reader
(** The embedded grammar, loaded into an engine, and the compiled query. *)

(** Why the reader does not start. *)
type load_error =
  | Grammar of Sinter_bridge.Language.error  (** the grammar does not load *)
  | Query of Sinter_bridge.Query.error  (** the query does not compile *)

val create : Sinter_bridge.t -> (reader, load_error) result
(** [create engine] loads the embedded grammar into [engine] and compiles the
    embedded query. The caller owns the result and frees it with {!close}. The
    reader stays valid while [engine] is open.

    @raise Invalid_argument if [engine] is closed.
    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)

val close : reader -> unit
(** [close reader] frees the grammar and the query of [reader]. Every later
    {!read} with [reader] raises [Invalid_argument]. A second call does nothing.
*)

(** {1 The structure of a file} *)

type heading = {
  text : string;
      (** the heading text: the line without its opening [#] characters and the
          indentation before them, without its closing sequence, without the
          spaces and tabs at both ends, and then without the section number at
          its start ({!Section_number}) *)
  slug : string;
      (** [text] with each ASCII letter made lowercase, each run of other
          characters than ASCII letters and digits made one [-], and the [-] at
          both ends removed *)
  name : string;
      (** [slug], numbered in the order of the file: the first heading of a slug
          keeps it, and a later one takes [slug-1], [slug-2], and so on, the
          first that no earlier heading took *)
  span : span;  (** from the first [#] to the last character of the line *)
}
(** The ATX heading that opens a section. *)

type section = {
  level : int;  (** from 1 to 6, the number of [#]; [0] for the level 0 *)
  heading : heading option;  (** [None] for the section of level 0 *)
  parent : int option;
      (** the index in {!field-sections} of the section that holds this one *)
  first_paragraph : span option;
      (** the tag-bearing first paragraph, from its first to its last character
          that is not a space, a tab, or a line ending *)
  extent : span option;
      (** the extent of the section: its lines after two changes, from column 1
          of the first line to the end of the last. The lines of each section
          inside it and of each list item inside it that holds a declaration in
          its first paragraph are removed, and then the blank lines at the end.
          A blank line holds only spaces and tabs. The section of level 0 starts
          at line 1, so it holds the front matter. [None] when no line is left.
      *)
}
(** One section. *)

(** The kind of tag-bearing node that holds a tag line. *)
type node =
  | Section_paragraph  (** the first paragraph of a section *)
  | Item_paragraph  (** the first paragraph of a list item *)

type extent = {
  first : int;  (** the first line of the extent *)
  last : int;  (** the last line of the extent, never a blank line *)
  hash : string;
      (** the extent hash, as 64 lowercase hexadecimal digits. On each heading
          line that opens a section, the hash leaves out the section number of
          the heading text, with the spaces and tabs after it. *)
}
(** The extent of a declaration. *)

type tag = {
  span : span;
      (** from the [@] to the last character of the line, the spaces and tabs at
          its end included *)
  word : string;  (** the tag word without its [@]; it can be empty *)
  rest : string;  (** the text of the line after the tag word *)
  target : string option;  (** the first token of [rest] *)
  rev : int option;
      (** [N] when the second token of [rest] is [vN], with [N] from 1 to 2^53 -
          1 and no leading zero *)
  desc : string;
      (** the inline description: the text of [rest] after the target and the
          revision, as it stands; [""] when there is none *)
  block : int;  (** the index in {!field-blocks} of the block of the line *)
  node : node;
  section : int;
      (** the index in {!field-sections} of the innermost section that holds the
          line *)
  owner : int option;
      (** the index in {!field-tags} of the declaration whose extent holds the
          line. For a declaration, it is the declaration itself. No two extents
          share a line. *)
  extent : extent option;  (** the extent, for a declaration alone *)
}
(** One tag line. *)

type block = {
  tags : int list;
      (** the indices in {!field-tags} of the tag lines, in the order of the
          lines; never empty *)
  prose : string list;
      (** the lines of the trailing prose, each without its line ending *)
  hash : string;
      (** the block hash, as 64 lowercase hexadecimal digits: the hash of the
          lines of the block, by the rule of the extent hash *)
}
(** One block: a run of tag lines of one tag-bearing node, and the trailing
    prose after them. *)

type t = {
  sections : section array;  (** in the order of the file *)
  tags : tag array;  (** every tag line, in the order of the file *)
  blocks : block array;  (** in the order of the file *)
  unread : span list;
      (** for each paragraph whose tags the reader does not read and whose first
          line is a tag line, the span of that tag line, in the order of the
          file. Such a paragraph is not the first paragraph of the section or
          the list item that holds it, and no block quote holds it. *)
  errors : span list;
      (** the places of the parse failures, in the order of the file: each
          [ERROR] node and each [MISSING] node that no [ERROR] node holds; when
          the tree flags a failure and shows no such node, the first lowest
          error node alone *)
}
(** The structure of one markdown file. The caller owns the arrays. *)

(** Why a file gives no structure. *)
type error =
  | Not_utf_8 of int
      (** the file is not UTF-8 text; the byte offset of its first sequence that
          is not well-formed *)
  | No_tree of Sinter_bridge.Tree.error  (** the parse gives no tree *)

val read : reader -> string -> (t, error) result
(** [read reader content] reads the bytes [content] of one markdown file. It
    adds a line feed at the end when [content] does not end with one. Every
    position of the result is a place of [content].

    @raise Invalid_argument if [reader] or its engine is closed.
    @raise Sinter_bridge.Error if the bridge stops on an internal fault. *)
