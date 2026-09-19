(** * The mathematical model: Fibonacci over Z.

    This file is deliberately free of any VST or CompCert dependency.  It is
    the "what should the program compute?" half of the specification, and you
    should be able to read and believe it without knowing anything about
    separation logic.  Everything downstream refers back to [fib]. *)

From Stdlib Require Import ZArith Lia.

Local Open Scope Z_scope.

(** The Fibonacci sequence: 0, 1, 1, 2, 3, 5, ...

    The nested [match] (rather than the more usual two-argument accumulator)
    is chosen so that the recurrence below holds by [reflexivity], which keeps
    the loop-invariant proof in [Verif_fib] to one line. *)
Fixpoint fib (n : nat) : Z :=
  match n with
  | O => 0
  | S n' => match n' with
            | O => 1
            | S n'' => fib n' + fib n''
            end
  end.

Lemma fib_O : fib 0 = 0.
Proof. reflexivity. Qed.

Lemma fib_1 : fib 1 = 1.
Proof. reflexivity. Qed.

(** The recurrence, in the shape the loop invariant needs. *)
Lemma fib_SS : forall n, fib (S (S n)) = fib (S n) + fib n.
Proof. reflexivity. Qed.

Lemma fib_nonneg : forall n, 0 <= fib n.
Proof.
  (* Two values at a time, since the recurrence looks back two steps. *)
  assert (H : forall n, 0 <= fib n /\ 0 <= fib (S n)).
  { induction n as [| n [IH1 IH2] ].
    - rewrite fib_O, fib_1; lia.
    - split; [ exact IH2 | rewrite fib_SS; lia ]. }
  intros n. apply (H n).
Qed.

(** [fib] is monotone, hence unbounded: this is why the C function can only
    be correct modulo 2^64, and why the specification says so explicitly. *)
Lemma fib_le_succ : forall n, fib (S n) <= fib (S (S n)).
Proof.
  intros n. rewrite fib_SS. pose proof (fib_nonneg n). lia.
Qed.
