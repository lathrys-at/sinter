(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** Branch names: the names that git accepts after [refs/heads/].

    A name is valid when [refs/heads/] and the name pass [git check-ref-format],
    and the name does not start with [refs/]. The module applies the rules of
    that command itself, and runs no process. A component is a part of the name
    between two [/], or before the first or after the last. *)

(** Why a string is not a branch name. Each offset is the offset, in bytes from
    0, of the first byte of the string that the error names. *)
type error =
  | Empty  (** the string is empty *)
  | Full_ref_name  (** the string starts with [refs/] *)
  | Bad_character of { offset : int; character : char }
      (** a control character, a space, the delete character, or one of
          [~ ^ : ? *], an opening bracket, and a backslash *)
  | Two_dots of int  (** two [.] together *)
  | At_brace of int  (** [@] and then [{] *)
  | Empty_component of int
      (** a [/] at the start or at the end, or two [/] together; the offset is
          that of the empty component *)
  | Component_starts_with_dot of int
      (** a component starts with [.]; the offset is that of the component *)
  | Component_ends_with_lock of int
      (** a component ends with [.lock]; the offset is that of the [.] *)
  | Ends_with_dot of int  (** the string ends with [.] *)

val check : string -> (unit, error) result
(** [check name] is [Ok ()] when [name] is a branch name. Otherwise it is the
    first error that git meets: git reads the components from the start, and in
    each component it reads the characters first and then the component as a
    whole. [Empty] and [Full_ref_name] come before every other error. *)

val error_offset : error -> int
(** [error_offset error] is the offset that [error] names. It is [0] for [Empty]
    and [Full_ref_name]. *)

val message : error -> string
(** [message error] says which rule the name breaks. It is one line, without the
    name itself and without a full stop at the end. *)
