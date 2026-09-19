(** * The I/O model: what the program must read, and what it must print.

    Observable behaviour in VST is expressed by an *interaction tree* held in
    the external-state ghost (see [VST.floyd.io_events] and
    [VST.progs64.io_specs]).  The tree [main_itree] below is the entire
    specification of the program's behaviour: reading it tells you exactly
    what the program does, without reference to any C code.

    The decimal-rendering function [chars_of_Z], its helper [intr], and the
    [Program Fixpoint] unfolding machinery are taken from VST's own
    [VST/progs64/verif_io.v] (VST is distributed under a BSD-style licence;
    see VST/LICENSE).  They are reproduced here rather than imported because
    that file also fixes a [compspecs] and an [Espec] for VST's example
    program, which would clash with ours. *)

Require Import VST.floyd.proofauto.
Require Import VST.progs64.io_specs.
Require Import FibVST.Fib_model.

Local Open Scope itree_scope.

(** ** Decimal rendering *)

Lemma div_10_dec : forall n, 0 < n ->
  (Z.to_nat (n / 10) < Z.to_nat n)%nat.
Proof.
  intros.
  change 10 with (Z.of_nat 10).
  rewrite <- (Z2Nat.id n) by lia.
  rewrite <- Nat2Z.inj_div by discriminate.
  rewrite !Nat2Z.id.
  apply Nat2Z.inj_lt.
  rewrite Nat2Z.inj_div, Z2Nat.id by lia; simpl.
  apply Z.div_lt; auto; lia.
Qed.

(** The digits of [n], for [n > 0]; [[]] for [n <= 0]. *)
Program Fixpoint intr n { measure (Z.to_nat n) } : list byte :=
  match n <=? 0 with
  | true => []
  | false => intr (n / 10) ++ [Byte.repr (n mod 10 + char0)]
  end.
Next Obligation.
Proof.
  rewrite ?Zaux.Zdiv_eucl_unique in *.
  apply div_10_dec.
  symmetry in Heq_anonymous; apply Z.leb_nle in Heq_anonymous; lia.
Defined.

(** The base-10 representation of [n]; [["0"]] for [n = 0]. *)
Program Fixpoint chars_of_Z (n : Z) { measure (Z.to_nat n) } : list byte :=
  let n' := n / 10 in
  match n' <=? 0 with
  | true => [Byte.repr (n + char0)]
  | false => chars_of_Z n' ++ [Byte.repr (n mod 10 + char0)]
  end.
Next Obligation.
Proof.
  rewrite ?Zaux.Zdiv_eucl_unique in *.
  apply div_10_dec.
  symmetry in Heq_anonymous; apply Z.leb_nle in Heq_anonymous.
  eapply Z.lt_le_trans, Z_mult_div_ge with (b := 10); lia.
Defined.

Import Program.Wf.
(** Copied from the Coq standard library, which moved it between 8.20 and
    8.21; VST's [verif_io.v] does the same. *)
Program Lemma fix_sub_eq_ext :
  forall (A : Type) (R : A -> A -> Prop) (Rwf : well_founded R)
    (P : A -> Type)
    (F_sub : forall x : A, (forall y:{y : A | R y x}, P (proj1_sig y)) -> P x),
    forall x : A,
      Fix_sub A R Rwf P F_sub x =
        F_sub x (fun y:{y : A | R y x} => Fix_sub A R Rwf P F_sub (proj1_sig y)).
Proof.
  intros A R Rwf P F_sub x; apply Fix_eq ; auto.
  intros ? f g H.
  assert(f = g) as H0.
  - extensionality y ; apply H.
  - rewrite H0 ; auto.
Qed.

Lemma intr_eq : forall n, intr n =
  match n <=? 0 with
  | true => []
  | false => intr (n / 10) ++ [Byte.repr (n mod 10 + char0)]
  end.
Proof.
  intros.
  unfold intr at 1.
  rewrite fix_sub_eq_ext; simpl; fold intr.
  destruct n; reflexivity.
Qed.

Lemma chars_of_Z_eq : forall n, chars_of_Z n =
  let n' := n / 10 in
  match n' <=? 0 with
  | true => [Byte.repr (n + char0)]
  | false => chars_of_Z n' ++ [Byte.repr (n mod 10 + char0)]
  end.
Proof.
  intros.
  unfold chars_of_Z at 1.
  rewrite fix_sub_eq_ext; simpl; fold chars_of_Z.
  destruct (_ <=? _); reflexivity.
Qed.

Lemma chars_of_Z_intr : forall n, 0 < n -> chars_of_Z n = intr n.
Proof.
  induction n using (well_founded_induction (Zwf.Zwf_well_founded 0)); intro.
  rewrite chars_of_Z_eq, intr_eq.
  destruct (n <=? 0) eqn: Hn; [apply Zle_bool_imp_le in Hn; lia|].
  simpl.
  rewrite ?Zaux.Zdiv_eucl_unique in *.
  destruct (n / 10 <=? 0) eqn: Hdiv.
  - apply Zle_bool_imp_le in Hdiv.
    assert (0 <= n / 10) by (apply Z.div_pos; lia).
    assert (n / 10 = 0) as Hz by lia.
    rewrite Hz; simpl.
    apply Z.div_small_iff in Hz as [|]; try lia.
    rewrite Zmod_small; auto.
  - apply Z.leb_nle in Hdiv.
    rewrite H; auto; try lia.
    split; try lia.
    apply Z.div_lt; auto; lia.
Qed.

(** ** Decimal parsing *)

(** The C code tests [c >= '0' && c <= '9']. *)
Definition is_digit (c : byte) : bool :=
  (char0 <=? Byte.unsigned c) && (Byte.unsigned c <=? char0 + 9).

Definition digit_val (c : byte) : Z := Byte.unsigned c - char0.

(** One step of the accumulator [n = n*10 + d], in unsigned 64-bit
    arithmetic, exactly as the C performs it. *)
Definition acc (n d : Z) : Z := (n * 10 + d) mod Int64.modulus.

(** Read a base-10 numeral from stdin.  Digits are accumulated modulo 2^64;
    the first non-digit character terminates the numeral and is consumed. *)
Definition read_num_from (n : Z) : itree (@IO_event nat) Z :=
  ITree.iter (fun n : Z =>
    c <- read stdin ;;
    if is_digit c
    then Ret (inl (acc n (digit_val c)))
    else Ret (inr n)) n.

Definition read_num : itree (@IO_event nat) Z := read_num_from 0.

(** ** The whole program's observable behaviour

    Read a decimal numeral [n] (mod 2^64), then print the base-10
    representation of the [n]-th Fibonacci number (mod 2^64), then a
    newline. *)
Definition fib_mod (n : Z) : Z := Int64.unsigned (Int64.repr (fib (Z.to_nat n))).

Definition main_itree : IO_itree :=
  n <- read_num ;;
  write_list stdout (chars_of_Z (fib_mod n)) ;;
  write stdout (Byte.repr newline).

(** [fib_mod] really is "the Fibonacci number, modulo 2^64". *)
Lemma fib_mod_eq : forall n, fib_mod n = fib (Z.to_nat n) mod 2 ^ 64.
Proof.
  intros n; unfold fib_mod.
  rewrite Int64.unsigned_repr_eq; reflexivity.
Qed.


(** The tree that remains once every prescribed interaction has happened.
    [main]'s postcondition says the program's tree has been consumed down to
    exactly this, i.e. it performed the prescribed I/O and nothing else. *)
Definition done : itree (@IO_event nat) unit := Ret tt.

(** ** Facts about the parser's arithmetic

    [dval c] is the value the C code actually computes into [d]:
    [(unsigned long)(c - '0')].  When [c] is below ['0'] the subtraction is
    performed on [int] and then widened, so the result wraps to something
    huge -- which is exactly why the single test [d < 10] correctly rejects
    both ends of the range. *)
Definition dval (c : byte) : Z := (Byte.unsigned c - char0) mod Int64.modulus.

Lemma byte_range : forall c : byte, 0 <= Byte.unsigned c <= 255.
Proof.
  intros c; pose proof (Byte.unsigned_range c).
  unfold Byte.modulus, Byte.wordsize, two_power_nat in *; simpl in *; lia.
Qed.

Lemma int64_modulus_val : Int64.modulus = 18446744073709551616.
Proof. reflexivity. Qed.

Lemma dval_range : forall c, 0 <= dval c < Int64.modulus.
Proof.
  intros; apply Z.mod_pos_bound; rewrite int64_modulus_val; lia.
Qed.

Lemma dval_lt_10 : forall c, is_digit c = true <-> dval c < 10.
Proof.
  intros c; pose proof (byte_range c).
  unfold is_digit, dval, char0 in *.
  rewrite int64_modulus_val in *.
  split.
  - intros Hd.
    apply andb_prop in Hd as [H1 H2].
    apply Z.leb_le in H1; apply Z.leb_le in H2.
    rewrite Z.mod_small by lia. lia.
  - intros Hd.
    destruct (Z.leb_spec 48 (Byte.unsigned c)) as [Hlo | Hlo].
    + rewrite Z.mod_small in Hd by lia.
      rewrite andb_true_iff; split; [ reflexivity | apply Z.leb_le; lia ].
    + (* the subtraction wrapped around, so d is enormous, not < 10 *)
      exfalso.
      rewrite <- (Z_mod_plus_full _ 1) in Hd.
      rewrite Z.mod_small in Hd by lia.
      lia.
Qed.

Lemma dval_digit_val : forall c, is_digit c = true -> dval c = digit_val c.
Proof.
  intros c Hd; pose proof (byte_range c).
  apply andb_prop in Hd as [H1 H2].
  apply Z.leb_le in H1; apply Z.leb_le in H2.
  unfold dval, digit_val, char0 in *.
  rewrite int64_modulus_val.
  apply Z.mod_small; lia.
Qed.

Lemma acc_range : forall n d, 0 <= acc n d < Int64.modulus.
Proof.
  intros; apply Z.mod_pos_bound; rewrite int64_modulus_val; lia.
Qed.

(** One step of the reader: consume a character, then either fold the digit
    into the accumulator and keep going, or stop. *)
Lemma read_num_from_eq : forall n,
  read_num_from n
  ≈ (c <- read stdin ;;
     if is_digit c then read_num_from (acc n (digit_val c)) else Ret n).
Proof.
  intros n.
  unfold read_num_from at 1; rewrite unfold_iter.
  rewrite bind_bind.
  apply eqit_bind; [ reflexivity | ].
  intros c.
  destruct (is_digit c); rewrite bind_ret_l.
  - rewrite tau_eutt; reflexivity.
  - reflexivity.
Qed.

(** [Int64.repr] already truncates, so the [mod] in [dval] is invisible to
    the C value. *)
Lemma dval_repr : forall c,
  Int64.repr (dval c) = Int64.repr (Byte.unsigned c - char0).
Proof.
  intros c; unfold dval.
  rewrite <- Int64.unsigned_repr_eq, Int64.repr_unsigned; reflexivity.
Qed.

(** [read_cont k n c] is what remains to be done after the reader has
    accumulated [n] and just consumed the character [c]: either fold [c] in
    and keep reading, or stop and hand [n] to the continuation [k]. *)
Definition read_cont (k : Z -> IO_itree) (n : Z) (c : byte) : IO_itree :=
  x <- (if is_digit c then read_num_from (acc n (digit_val c)) else Ret n) ;; k x.

Lemma read_num_bind : forall k n,
  (x <- read_num_from n ;; k x) ≈ (c <- read stdin ;; read_cont k n c).
Proof.
  intros; unfold read_cont.
  rewrite read_num_from_eq, bind_bind; reflexivity.
Qed.

Lemma read_cont_digit : forall k n c, is_digit c = true ->
  read_cont k n c ≈ (c' <- read stdin ;; read_cont k (acc n (digit_val c)) c').
Proof.
  intros k n c Hd; unfold read_cont at 1; rewrite Hd.
  apply read_num_bind.
Qed.

Lemma read_cont_stop : forall k n c, is_digit c = false -> read_cont k n c ≈ k n.
Proof.
  intros k n c Hd; unfold read_cont; rewrite Hd, bind_ret_l; reflexivity.
Qed.

Lemma acc_repr : forall n d, Int64.repr (acc n d) = Int64.repr (n * 10 + d).
Proof.
  intros; unfold acc.
  rewrite <- Int64.unsigned_repr_eq, Int64.repr_unsigned; reflexivity.
Qed.

(** The value the C stores in [d]: [(unsigned long)(c - '0')], computed as an
    [int] subtraction and then widened. *)
Lemma dval_sub_repr : forall c,
  Int64.repr (Int.signed (Int.sub (Int.repr (Byte.unsigned c)) (Int.repr 48)))
  = Int64.repr (dval c).
Proof.
  intros c; pose proof (byte_range c).
  rewrite dval_repr, sub_repr, Int.signed_repr by rep_lia.
  unfold char0; reflexivity.
Qed.

Lemma fib_mod_range : forall n, 0 <= fib_mod n <= Int64.max_unsigned.
Proof.
  intros; unfold fib_mod; apply Int64.unsigned_range_2.
Qed.

Lemma fib_mod_repr : forall n,
  Int64.repr (fib_mod n) = Int64.repr (fib (Z.to_nat n)).
Proof.
  intros; unfold fib_mod; apply Int64.repr_unsigned.
Qed.
