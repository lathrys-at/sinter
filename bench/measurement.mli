(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

(** The measures of one run of a command, read from the output of [time] and
    [perf stat], and the summary of several runs. *)

type sample = {
  peak_kib : int;  (** the peak resident memory, in KiB *)
  instructions : int option;
      (** the instructions that the process retired, when the platform counts
          them *)
  footprint_kib : int option;
      (** the peak memory footprint that macOS reports, in KiB *)
}
(** The measures of one run. *)

val gnu_time : string -> (int, string) result
(** [gnu_time text] is the peak resident memory in KiB, from [text], the file
    that GNU [time -f %M -o FILE] writes: the last line that is not empty holds
    one decimal number. Every line before it, such as the line that GNU [time]
    writes when the command exits with a status that is not 0, is ignored. The
    error says what the text lacks. *)

val bsd_time : string -> (sample, string) result
(** [bsd_time text] is the sample from [text], the file that the
    [time -l -o FILE] of macOS writes. The lines ["maximum resident set size"]
    and ["peak memory footprint"] give bytes, which the sample holds in KiB,
    rounded down; the line ["instructions retired"] gives the instructions. The
    line of the resident set size is required; a missing line of the footprint
    or of the instructions gives [None]. The error says what the text lacks. *)

val perf_stat : string -> (int option, string) result
(** [perf_stat text] is the instruction count from [text], the file that
    [perf stat -x, -e instructions:u -o FILE] writes. Lines that start with [#]
    and empty lines are ignored. Each other line holds fields separated by
    commas; the count is the sum of the first fields of the lines whose third
    field holds [instructions], such as [cpu_core/instructions:u/] on a CPU of
    two kinds of core. A first field of [<not counted>] or [<not supported>]
    adds nothing. The count is [None] when no line adds to it. The error says
    what the text lacks. *)

val phase_words : string -> ((string * int) list, string) result
(** [phase_words text] is each phase of [text], the file that [sinter] writes
    when the environment variable [SINTER_PHASE_WORDS] names it: one line for
    each phase, with the name, one space, and the words in decimal, and a line
    feed at the end of each line. The phases are in the order of the lines. The
    error names the first line that is not of that form, or a name that occurs
    twice. *)

type summary = {
  median : float;
  min : float;
  max : float;
  spread : float;
      (** [(max - min) / median], in percent; [0.] when the median is [0.] *)
}
(** The summary of the values of several runs. *)

val summary : float list -> summary
(** [summary values] is the summary of [values]. The median of an even number of
    values is the mean of the two values in the middle.

    @raise Invalid_argument if [values] is empty. *)
