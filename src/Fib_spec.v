(** * The interface exported by the [fib.c] compilation unit.

    This is the whole of fib.c's contract with the rest of the program:
    [main.c] is verified against this file alone, and never sees
    [fib.c]'s body.  Keeping it in its own file is what makes that
    separation visible: [Verif_main.v] never mentions [f_fib], only
    [fib_spec]. *)

Require Import VST.floyd.proofauto.
Require Import FibVST.fib.
Require Import FibVST.Fib_model.

Local Open Scope assert.

(** [fib(n)] is the n-th Fibonacci number, truncated to 64 bits.

    The precondition admits the entire range of [unsigned long], so this is a
    total specification: there is no input for which the C function may
    misbehave.  [Int64.repr] is the truncation; [Int64.unsigned_repr_eq] turns
    the postcondition into the "mod 2^64" form if you prefer to read it that
    way (see [Fib_model.fib_mod_eq]). *)
Definition fib_spec : ident * funspec :=
 DECLARE _fib
  WITH n : Z
  PRE [ tulong ]
    PROP (0 <= n <= Int64.max_unsigned)
    PARAMS (Vlong (Int64.repr n))
    GLOBALS ()
    SEP ()
  POST [ tulong ]
    PROP ()
    RETURN (Vlong (Int64.repr (fib (Z.to_nat n))))
    SEP ().

Definition Fib_ASI : funspecs := [fib_spec].
