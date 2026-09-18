#ifndef FIB_H
#define FIB_H

/* Compute the n-th Fibonacci number, modulo 2^64.

   fib(0) = 0, fib(1) = 1, fib(n+2) = fib(n+1) + fib(n), with the additions
   performed in unsigned long arithmetic, i.e. modulo 2^64.  This is exact for
   n <= 93; beyond that the mathematical value does not fit in 64 bits and the
   result is its residue mod 2^64.  The Coq specification says exactly this,
   for every n in [0, 2^64). */
unsigned long fib(unsigned long n);

#endif
