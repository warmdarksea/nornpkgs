#include "fib.h"

extern int getchar(void);
extern int putchar(int c);

/* getchar/putchar are specified as possibly returning -1 without making
   progress (see VST/progs64/io_specs.v); retry until they commit.  These two
   wrappers, and their proofs, are taken from VST's own progs64/io.c. */

int getchar_blocking(void) {
  int r = -1;
  while (r == -1) r = getchar();
  return r;
}

int putchar_blocking(int c) {
  int r = -1;
  while (r == -1) r = putchar(c);
  return r;
}

/* Read a base-10 numeral from stdin, accumulating modulo 2^64.  The first
   non-digit terminates the numeral and is consumed.

   The digit test is done on the unsigned difference, as in VST's io.c: if c
   is below '0' the subtraction wraps around to a huge value, so the single
   comparison d < 10 covers both ends of the range. */
unsigned long read_ulong(void) {
  unsigned long n = 0;
  unsigned long d;
  int c;
  c = getchar_blocking();
  d = (unsigned long)(c - '0');
  while (d < 10) {
    n = n * 10 + d;
    c = getchar_blocking();
    d = (unsigned long)(c - '0');
  }
  return n;
}

/* Print i in base 10; requires i != 0.  (The most significant digit is
   emitted first, by recursing before printing.) */
void print_ulong_aux(unsigned long i) {
  unsigned long q, r;
  if (i != 0) {
    q = i / 10;
    r = i % 10;
    print_ulong_aux(q);
    putchar_blocking((int)r + '0');
  }
}

/* Print i in base 10, for any i.  This is the verified "%lu". */
void print_ulong(unsigned long i) {
  if (i == 0)
    putchar_blocking('0');
  else
    print_ulong_aux(i);
}

int main(void) {
  unsigned long n, f;
  n = read_ulong();
  f = fib(n);
  print_ulong(f);
  putchar_blocking('\n');
  return 0;
}
