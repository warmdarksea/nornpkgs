(** * Proof 1: [fib.c] computes the Fibonacci function.

    This discharges [fib_spec] for every [n] in the whole [unsigned long]
    range: the precondition is [0 <= n <= Int64.max_unsigned], so there is no
    input on which the C function may misbehave.

    Note what the proof script below does *not* mention: anything from
    [main.c].  The only reason this file refers to the linked program at all
    is that VST's [semax_body] is stated relative to an ambient varspec and
    funspec table. *)

Require Import VST.floyd.proofauto.
Require Import FibVST.fib.
Require Import FibVST.Fib_model.
Require Import FibVST.Fib_spec.
Require Import FibVST.Whole_prog.
Require Import FibVST.Main_spec.

(** The loop maintains [a = fib i] and [b = fib (i+1)], truncated to 64 bits.

    Stating the invariant with [Int64.repr (fib i)] rather than an explicit
    [fib i mod 2^64] is what keeps this short: [entailer!] already rewrites
    with [add64_repr] (it is in the [entailer_rewrite] hint database), so the
    loop step reduces to the recurrence [fib_SS] plus arithmetic. *)
Lemma body_fib : semax_body Vprog Gprog f_fib fib_spec.
Proof.
  start_function.
  forward.
  forward.
  forward_for_simple_bound n
    (EX i : Z,
      PROP ()
      LOCAL (temp _a (Vlong (Int64.repr (fib (Z.to_nat i))));
             temp _b (Vlong (Int64.repr (fib (S (Z.to_nat i)))));
             temp _n (Vlong (Int64.repr n)))
      SEP ())%assert.
  - entailer!.
  - forward. forward. forward.
    entailer!.
    replace (Z.to_nat (i + 1)) with (S (Z.to_nat i))
      by (rewrite Z2Nat.inj_add by lia; simpl; lia).
    rewrite fib_SS.
    split; [ reflexivity | do 2 f_equal; lia ].
  - forward.
Qed.
