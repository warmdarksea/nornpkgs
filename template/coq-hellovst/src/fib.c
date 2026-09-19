#include "fib.h"

unsigned long fib(unsigned long n) {
  unsigned long a = 0, b = 1, i;
  for (i = 0; i < n; i++) {
    unsigned long t = a + b;
    a = b;
    b = t;
  }
  return a;
}
