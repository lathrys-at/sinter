/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 The Sinter Authors */

/* @cites repository-file-reads */

#include <fcntl.h>

#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <caml/unixsupport.h>

CAMLprim value sinter_repo_file_open_at(value folder, value name, value last) {
  CAMLparam3(folder, name, last);
  int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NOCTTY |
              (Bool_val(last) ? O_NONBLOCK : O_DIRECTORY);
  caml_unix_check_path(name, "openat");
  char *copy = caml_stat_strdup(String_val(name));
  caml_enter_blocking_section();
  int handle = openat(Int_val(folder), copy, flags);
  caml_leave_blocking_section();
  caml_stat_free(copy);
  if (handle == -1) {
    caml_uerror("openat", name);
  }
  CAMLreturn(Val_int(handle));
}
