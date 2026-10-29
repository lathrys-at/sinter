(* SPDX-License-Identifier: Apache-2.0 *)
(* Copyright 2026 The Sinter Authors *)

type element =
  | Block
  | Warn
  | Headline
  | Frame
  | Help
  | Inserted
  | Removed
  | Note
  | Plain

let styles = function
  | Block -> [ `Bold; `Fg (`Hi `Red) ]
  | Warn -> [ `Bold; `Fg `Yellow ]
  | Headline | Note -> [ `Bold ]
  | Frame -> [ `Bold; `Fg (`Hi `Blue) ]
  | Help -> [ `Bold; `Fg `Cyan ]
  | Inserted -> [ `Fg `Green ]
  | Removed -> [ `Fg `Red ]
  | Plain -> []

let of_tier = function
  | Some Finding_class.Block -> Block
  | Some Finding_class.Warn -> Warn
  | Some Finding_class.Off | None -> Headline

let printer element =
  List.fold_right
    (fun style pp -> Fmt.styled style pp)
    (styles element) Fmt.string

let block = printer Block
and warn = printer Warn
and headline = printer Headline
and frame = printer Frame
and help = printer Help
and inserted = printer Inserted
and removed = printer Removed
and note = printer Note

let string = function
  | Block -> block
  | Warn -> warn
  | Headline -> headline
  | Frame -> frame
  | Help -> help
  | Inserted -> inserted
  | Removed -> removed
  | Note -> note
  | Plain -> Fmt.string

type setting = Auto | Always | Never

let given getenv name =
  match getenv name with Some "" | None -> None | Some value -> Some value

let color setting ~getenv ~terminal =
  match setting with
  | Always -> true
  | Never -> false
  | Auto -> (
      match
        ( given getenv "NO_COLOR",
          getenv "CLICOLOR_FORCE",
          given getenv "FORCE_COLOR" )
      with
      | Some _, _, _ -> false
      | None, Some force, _ when force <> "0" -> true
      | None, _, Some _ -> true
      | None, _, None ->
          getenv "TERM" <> Some "dumb"
          && getenv "CLICOLOR" <> Some "0"
          && terminal)

let renderer color = if color then `Ansi_tty else `None

let prepare ppf renderer =
  Format.pp_set_geometry ppf ~max_indent:(Format.pp_infinity - 2)
    ~margin:(Format.pp_infinity - 1);
  Fmt.set_style_renderer ppf renderer

let formatter channel ~color =
  let ppf = Format.formatter_of_out_channel channel in
  prepare ppf (renderer color);
  ppf
