///bin/true; (test "$0" -ot "$0.tmp" || cc "$0" -o "$0.tmp") && "$0.tmp" "$@"; exit $?

#include <stdio.h>

int main() {
  printf("OK!\n");
  return 0;
}
