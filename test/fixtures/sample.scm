; SPDX-License-Identifier: Apache-2.0
; Copyright 2026 The Sinter Authors

; The key and the value of every pair whose value is a string.
(pair
  key: (string (string_content) @key)
  value: (string (string_content) @value))

; Every number.
(number) @number
