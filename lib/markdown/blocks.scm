; SPDX-License-Identifier: Apache-2.0
; Copyright 2026 The Sinter Authors

; Every block of a markdown file that the reader needs, with one capture
; name. The reader rebuilds the nesting of the blocks from their ranges.
[
  (section)
  (atx_heading)
  (setext_heading)
  (paragraph)
  (list_item)
  (block_quote)
  (thematic_break)
  (indented_code_block)
  (fenced_code_block)
  (html_block)
  (link_reference_definition)
  (pipe_table)
] @block
