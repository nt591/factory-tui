#define _GNU_SOURCE
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/alloc.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

extern char **environ;

CAMLprim value factory_monotonic(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(result);
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
    caml_failwith("Cannot read monotonic clock.");
  result = caml_copy_double(now.tv_sec + now.tv_nsec / 1000000000.0);
  CAMLreturn(result);
}

CAMLprim value factory_spawn(value executable, value args, value descriptors,
                             value directory) {
  CAMLparam4(executable, args, descriptors, directory);
  posix_spawn_file_actions_t actions;
  posix_spawnattr_t attributes;
  pid_t pid = 0;
  int error = 0;
  size_t count = Wosize_val(args);
  char **argv = calloc(count + 2, sizeof(char *));
  if (!argv) caml_raise_out_of_memory();
  argv[0] = strdup(String_val(executable));
  for (size_t i = 0; i < count; i++) argv[i + 1] = strdup(String_val(Field(args, i)));
  for (size_t i = 0; i < count + 1; i++) {
    if (!argv[i]) {
      for (size_t j = 0; j < count + 1; j++) free(argv[j]);
      free(argv);
      caml_raise_out_of_memory();
    }
  }
  error = posix_spawn_file_actions_init(&actions);
  if (error) goto cleanup;
  error = posix_spawnattr_init(&attributes);
  if (error) goto cleanup_actions;
  for (int i = 0; i < 3; i++) {
    int fd = Int_val(Field(descriptors, i));
    error = posix_spawn_file_actions_adddup2(&actions, fd, i);
    if (error) goto cleanup_attributes;
    error = posix_spawn_file_actions_addclose(&actions, fd);
    if (error) goto cleanup_attributes;
  }
  error = posix_spawn_file_actions_addchdir_np(&actions, String_val(directory));
  if (error) goto cleanup_attributes;
  /* The child group lets cancellation include ordinary descendants. */
  error = posix_spawnattr_setpgroup(&attributes, 0);
  if (error) goto cleanup_attributes;
  error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
  if (error) goto cleanup_attributes;
  error = posix_spawn(&pid, String_val(executable), &actions, &attributes, argv, environ);
cleanup_attributes:
  posix_spawnattr_destroy(&attributes);
cleanup_actions:
  posix_spawn_file_actions_destroy(&actions);
cleanup:
  for (size_t i = 0; i < count + 1; i++) free(argv[i]);
  free(argv);
  if (error) caml_failwith("Cannot start harness process.");
  CAMLreturn(Val_int(pid));
}
