#define _GNU_SOURCE
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/alloc.h>
#include <time.h>

CAMLprim value factory_monotonic(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(result);
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
    caml_failwith("Cannot read monotonic clock.");
  result = caml_copy_double(now.tv_sec + now.tv_nsec / 1000000000.0);
  CAMLreturn(result);
}

