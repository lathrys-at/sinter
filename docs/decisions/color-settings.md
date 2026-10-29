<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- Copyright 2026 The Sinter Authors -->

# Color the text output with the 16 base colors, by a fixed order of settings
@decision color-settings
@cites output-forms
@cites own-renderer
Sinter colors its full and brief forms and its messages with the 16 base colors of the terminal and bold, and it decides for each output stream by the option `--color`, then `NO_COLOR`, then `CLICOLOR_FORCE` and `FORCE_COLOR`, then `TERM` and `CLICOLOR`, then whether the stream is a terminal.

## Context

The full form of `output-forms` has many parts: the tier, the
headline, the frame of the source lines, the marks, the help, and the
lines of a fix. Color makes the parts easy to tell apart. The library
`fmt` of `own-renderer` writes styles, but it reads no environment
variable, so Sinter must decide itself when to use color. The tools
check the settings in different orders. The `NO_COLOR` convention turns
color off; the `FORCE_COLOR` convention turns it on and lets
`FORCE_COLOR` win over `NO_COLOR`; cargo lets `NO_COLOR` win. A
terminal theme can have a dark or a light background.

## Decision

- Sinter uses only the 16 base colors and bold. The terminal theme sets
  the shades.

  | element | style |
  |---|---|
  | `block[…]`, its marks, `error:` | bold bright red |
  | `warn[…]`, its marks, `warning:` | bold yellow |
  | the headline | bold |
  | `-->`, `:::`, the gutter, the line numbers, the labels of related places | bold bright blue |
  | `help:`, `fix:` | bold cyan |
  | an inserted line of a fix | green |
  | a removed line of a fix | red |
  | `note:` | bold |
  | paths, details, and source lines | no style |

- The option `--color=auto|always|never` is on every command, and
  `auto` is the default. The first rule that matches decides:
  1. `--color=always` or `--color=never`.
  2. `NO_COLOR` is set and not empty: no color.
  3. `CLICOLOR_FORCE` is set and not `0`, or `FORCE_COLOR` is set and
     not empty: color.
  4. `TERM` is `dumb`, or `CLICOLOR` is `0`: no color.
  5. Otherwise: color when the stream is a terminal.
- Sinter decides for standard output and for standard error apart, so
  the findings can go to a file while the summary goes to a terminal.
- JSON output, and later the porcelain form, never has color, not even
  with `--color=always`.
- No color means no escape code at all. With the escape codes removed,
  the colored text is the same as the text with no color.
- The help names the five variables and the order.

## Alternatives considered

- **The order of the `FORCE_COLOR` convention**, in which
  `FORCE_COLOR` wins over `NO_COLOR`. Not chosen: a person who sets
  `NO_COLOR` asked for no color, and a variable that another tool sets
  must not override that request.

## Consequences

The tests compare the text with no color, and a few tests force color
on to check the styles. A script that reads the full or the brief form
through a pipe gets no escape codes unless it asks for them. A palette
of 256 colors or of exact shades would need a new decision.
