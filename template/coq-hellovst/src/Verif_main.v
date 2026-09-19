(** * Proof 2 (bodies): [main.c] reads a number and prints its Fibonacci.

    [Link.v] assembles these into the whole-program theorem.

    [body_getchar_blocking] and [body_putchar_blocking] are VST's own proofs
    from [VST/progs64/verif_io.v]: [main.c] wraps [getchar]/[putchar] exactly
    as VST's [io.c] does, so those scripts apply unchanged. *)

Require Import VST.floyd.proofauto.
Require Import VST.progs64.io_specs.
Require Import FibVST.main.
Require Import FibVST.Fib_model.
Require Import FibVST.Fib_spec.
Require Import FibVST.IO_model.
Require Import FibVST.Whole_prog.
Require Import FibVST.Main_spec.

Local Open Scope itree_scope.

Lemma signed_char_unsigned : forall c, Byte.unsigned c <= two_p 8 - 1.
Proof.
  intros.
  pose proof (Byte.unsigned_range c).
  unfold Byte.modulus, two_power_nat in H; simpl in *; lia.
Qed.

Lemma modu64_repr : forall x y,
  0 <= x <= Int64.max_unsigned -> 0 <= y <= Int64.max_unsigned ->
  Int64.modu (Int64.repr x) (Int64.repr y) = Int64.repr (x mod y).
Proof.
  intros; unfold Int64.modu.
  rewrite !Int64.unsigned_repr; auto.
Qed.

Lemma body_getchar_blocking :
  semax_body Vprog Gprog f_getchar_blocking getchar_blocking_spec.
Proof.
  start_function.
  forward.
  forward_while (EX i : int,
    PROP (-1 <= Int.signed i <= two_p 8 - 1)
    LOCAL (temp _r (Vint i))
    SEP (ITREE (if eq_dec (Int.signed i) (-1)
                then (r <- read stdin;; k r) else k (Byte.repr (Int.signed i))))).
  - Exists (Int.neg (Int.repr 1)); entailer!.
    { simpl; lia. }
    rewrite if_true; auto.
  - entailer!.
  - subst; rewrite Int.signed_repr by rep_lia.
    rewrite if_true by auto.
    forward_call k.
    Intros i.
    forward.
    Exists i; entailer!.
  - assert (Int.signed i <> -1).
    { intro X.
      apply f_equal with (f := Int.repr) in X.
      rewrite Int.repr_signed in X; auto. }
    rewrite if_false by auto.
    forward.
    Exists (Byte.repr (Int.signed i)); entailer!.
    unfold Vubyte; rewrite Byte.unsigned_repr, Int.repr_signed; auto.
    split; try lia.
    etransitivity; [apply H|].
    simpl; rep_lia.
Qed.

Lemma body_putchar_blocking :
  semax_body Vprog Gprog f_putchar_blocking putchar_blocking_spec.
Proof.
  start_function.
  forward.
  forward_while (EX i : int,
    PROP (Int.signed i = -1 \/ Int.signed i = Byte.unsigned c)
    LOCAL (temp _r (Vint i); temp _c (Vubyte c))
    SEP (ITREE (if eq_dec (Int.signed i) (-1) then (r <- write stdout c;; k) else k))).
  - Exists (Int.neg (Int.repr 1)); entailer!.
    rewrite if_true; auto.
  - entailer!.
  - subst; rewrite Int.signed_repr by rep_lia.
    rewrite if_true by auto.
    forward_call (c, k).
    Intros i.
    forward.
    Exists i; entailer!.
  - assert (Int.signed i <> -1).
    { intro X.
      apply f_equal with (f := Int.repr) in X.
      rewrite Int.repr_signed in X; auto. }
    rewrite if_false by auto.
    destruct H; [contradiction | subst].
    forward.
    entailer!.
    unfold Vubyte.
    rewrite <- H, Int.repr_signed; auto.
Qed.

(** [print_ulong_aux] emits the digits of [i] most-significant first, by
    recursing on [i/10] before printing [i mod 10].  The proof mirrors VST's
    [body_print_intr], at 64 bits instead of 32. *)
Lemma body_print_ulong_aux :
  semax_body Vprog Gprog f_print_ulong_aux print_ulong_aux_spec.
Proof.
  start_function.
  forward_if (PROP () LOCAL () SEP (ITREE tr)).
  - forward. forward.
    rewrite modu64_repr, divu_repr64 by (lia || computable).
    change (Int.signed (Int.repr 10)) with 10.
    assert (Hi : 0 < i) by (destruct (Z.eq_dec i 0); [subst; congruence | lia]).
    rewrite intr_eq.
    destruct (Z.leb_spec i 0); try lia.
    rewrite write_list_app, bind_bind.
    (* the recursive call prints all but the last digit *)
    forward_call (i / 10, write_list stdout [Byte.repr (i mod 10 + char0)];; tr).
    { split; [apply Z.div_pos; lia | apply Z.div_le_upper_bound; lia]. }
    simpl write_list.
    (* ... and this call prints the last one *)
    forward_call (Byte.repr (i mod 10 + char0), tr).
    { (* the (int)r + '0' addition does not overflow *)
      pose proof (Z_mod_lt i 10 ltac:(lia)).
      rewrite Int64.Z_mod_modulus_eq, Zmod_small by rep_lia.
      rewrite !Int.signed_repr by rep_lia; rep_lia. }
    { (* the argument really is the byte for digit [i mod 10] *)
      entailer!.
      pose proof (Z_mod_lt i 10 ltac:(lia)).
      simpl; unfold Vubyte, char0.
      rewrite Int64.Z_mod_modulus_eq, Zmod_small by rep_lia.
      rewrite Byte.unsigned_repr by rep_lia.
      reflexivity. }
    { rewrite <- sepcon_emp at 1; apply sepcon_derives; [|cancel].
      rewrite bind_ret'; auto. }
    entailer!.
  - forward.
    (* the [i = 0] branch prints nothing; the tree must already be [tr] *)
    assert (i = 0) as Hz
      by (rewrite <- (Int64.unsigned_repr i) by rep_lia; rewrite H0; reflexivity).
    subst i.
    entailer!.
    rewrite intr_eq; simpl.
    rewrite bind_ret_l; auto.
Qed.

(** [print_ulong] is the verified ["%lu"]: it prints [chars_of_Z i], the
    base-10 representation of [i].  The only difference from
    [print_ulong_aux] is the [i = 0] case, which must still print a digit. *)
Lemma body_print_ulong : semax_body Vprog Gprog f_print_ulong print_ulong_spec.
Proof.
  start_function.
  forward_if (PROP () LOCAL () SEP (ITREE tr)).
  - assert (i = 0) as Hz
      by (rewrite <- (Int64.unsigned_repr i) by rep_lia; rewrite H0; reflexivity).
    subst i.
    forward_call (Byte.repr char0, tr).
    { rewrite chars_of_Z_eq; simpl.
      erewrite <- sepcon_emp at 1; apply sepcon_derives; [|cancel].
      rewrite bind_ret'; apply derives_refl. }
    entailer!.
  - assert (Hi : 0 < i) by (destruct (Z.eq_dec i 0); [subst; congruence | lia]).
    forward_call (i, tr).
    { rewrite chars_of_Z_intr by lia; cancel. }
    entailer!.
Qed.

(** [read_ulong] is the verified [atol]: it folds decimal digits into an
    accumulator until a non-digit arrives.  The loop invariant pairs the
    accumulator [n] with the character [c] just read, and says the remaining
    interaction tree is [read_cont k n c]. *)
Lemma body_read_ulong : semax_body Vprog Gprog f_read_ulong read_ulong_spec.
Proof.
  start_function.
  forward.
  unfold read_num; rewrite read_num_bind.
  forward_call (read_cont k 0).
  Intros c.
  forward.
  forward_while (EX n : Z, EX c : byte,
    PROP (0 <= n < Int64.modulus)
    LOCAL (temp _n (Vlong (Int64.repr n));
           temp _d (Vlong (Int64.repr (dval c)));
           temp _c (Vubyte c))
    SEP (ITREE (read_cont k n c))).
  - Exists 0 c; entailer!.
    rewrite dval_repr; reflexivity.
  - entailer!.
  - (* loop body: the test [d < 10] means [c0] is a digit *)
    assert (Hd : is_digit c0 = true).
    { apply dval_lt_10.
      pose proof (dval_range c0).
      rewrite !Int64.unsigned_repr in HRE by rep_lia; auto. }
    rewrite (ITREE_ext _ _ (read_cont_digit k n c0 Hd)).
    forward.
    forward_call (read_cont k (acc n (digit_val c0))).
    Intros c'.
    forward.
    Exists (acc n (digit_val c0), c'); entailer!.
    + repeat split.
      * apply acc_range.
      * apply acc_range.
      * rewrite acc_repr, (dval_digit_val _ Hd); reflexivity.
      * rewrite dval_repr; reflexivity.
    + apply derives_refl.
  - (* loop exit: the test failed, so [c0] is not a digit and the reader stops *)
    assert (Hd : is_digit c0 = false).
    { destruct (is_digit c0) eqn:E; auto.
      apply dval_lt_10 in E.
      pose proof (dval_range c0).
      rewrite !Int64.unsigned_repr in HRE by rep_lia; lia. }
    rewrite (ITREE_ext _ _ (read_cont_stop k n c0 Hd)).
    forward.
    Exists n; entailer!.
Qed.

(** [main] ties the two compilation units together: it reads a number with
    [read_ulong], hands it to [fib] (which it knows only through [fib_spec],
    the interface [fib.c] exports), prints the result with [print_ulong], and
    emits a newline.  Threading [main_itree] through those four calls is
    exactly the end-to-end statement. *)
Lemma body_main : semax_body Vprog Gprog f_main main_spec.
Proof.
  start_function.
  (* [main_pre] for this program is just the oracle: it declares no globals.
     VST's [expand_main_pre] only fires when the program is syntactically a
     [Clightdefs.mkprogram], which a linked program is not, so do it by
     hand. *)
  eapply semax_pre with (PROP () LOCAL (gvars gv) SEP (ITREE main_itree)).
  { unfold main_pre_old.
    assert (Hv : prog_vars linked_prog = nil) by reflexivity.
    rewrite Hv; unfold globvars2pred; simpl.
    go_lowerx.
    rewrite emp_sepcon, sepcon_emp.
    entailer!.
    apply has_ext_ITREE. }
  unfold main_itree.
  forward_call (fun n : Z =>
    write_list stdout (chars_of_Z (fib_mod n)) ;; write stdout (Byte.repr newline)).
  Intros n.
  (* main knows [fib] only through [fib_spec] -- it never sees [f_fib] *)
  forward_call n.
  forward_call (fib_mod n, write stdout (Byte.repr newline)).
  { rewrite fib_mod_repr; entailer!. }
  { pose proof (fib_mod_range n); rep_lia. }
  (* the final newline: [write c] is [write c ;; Ret tt] up to eutt *)
  rewrite <- (ITREE_ext _ _ (bind_ret' _ (write stdout (Byte.repr newline)))).
  forward_call (Byte.repr newline, done).
  { unfold done; cancel. }
  forward.
Qed.
