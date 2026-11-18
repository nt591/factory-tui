#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>
#include <sys/socket.h>
#include <errno.h>

CAMLprim value factory_socket_no_sigpipe(value fd) {
  CAMLparam1(fd);
#if defined(SO_NOSIGPIPE)
  int enabled = 1;
  if (setsockopt(Int_val(fd), SOL_SOCKET, SO_NOSIGPIPE,
                 &enabled, sizeof(enabled)) != 0)
    caml_unix_error(errno, "setsockopt", Nothing);
#elif !defined(MSG_NOSIGNAL)
#error "Socket input requires per-socket SIGPIPE suppression."
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value factory_socket_send(value fd, value bytes, value offset, value length) {
  CAMLparam4(fd, bytes, offset, length);
  ssize_t count;
  int flags = 0;
#if defined(MSG_NOSIGNAL)
  flags = MSG_NOSIGNAL;
#endif
  /* The socket is nonblocking. Keep the runtime lock while accessing these bytes. */
  count = send(Int_val(fd), Bytes_val(bytes) + Long_val(offset), Long_val(length), flags);
  if (count < 0) caml_unix_error(errno, "send", Nothing);
  CAMLreturn(Val_long(count));
}
