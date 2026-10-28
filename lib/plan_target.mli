(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The tag target of [@plan]: a slug, or the full form of a plan, a slug, [@],
    and a plan id. *)

type id = private string
(** A plan id: exactly six lowercase hexadecimal digits, [[0-9a-f]{6}]. *)

val id_of_string : string -> id option
(** [id_of_string text] is [text] as a plan id, or [None] when [text] is not
    exactly six lowercase hexadecimal digits. *)

type t = { slug : string; id : id option }
(** A plan target: the slug, and the plan id when the target has one. *)

(** Why a tag target is not a plan target. *)
type error =
  | Invalid_slug of string
      (** the text before the first [@], or the whole target when it holds no
          [@], fails the slug pattern of {!Slug.is_valid} *)
  | Invalid_id of string
      (** the slug is valid, and the text after the first [@] is not a plan id
      *)

val parse : string -> (t, error) result
(** [parse text] reads [text] as a plan target. When [text] holds no [@], the
    whole text is the slug and the target has no id. Otherwise the slug is the
    text before the first [@], and the id is the text after it. *)

val to_string : t -> string
(** [to_string target] is the full form of [target]: the slug, then [@] and the
    id when [target] has an id. [parse (to_string target)] is [Ok target] when
    the slug of [target] is valid. *)
