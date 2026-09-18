Require Import VST.floyd.proofauto.
Require Import VST.floyd.extcall_lemmas.
Require Import VST.progs64.io_specs.
Require Import VST.veric.SequentialClight.
Require Import VST.veric.tcb.
Require Import VST.progs64.io_dry.
Require Import FibVST.IO_model.
Require Import FibVST.Fib_spec.
Require Import FibVST.Whole_prog.
Require Import FibVST.Main_spec.
Require Import FibVST.Verif_fib.
Require Import FibVST.Verif_main.

Import extcall_lemmas.

(** VST's [prove_semax_prog] discharges the compspecs side condition with
    [solve_cenvcs_goal], which pattern-matches on the program being a
    [Clightdefs.mkprogram].  A *linked* program is not one, so that step is
    replaced by plain [reflexivity] here -- which suffices because neither
    translation unit declares a struct or union, so both composite
    environments are empty.  Everything else is VST's tactic verbatim. *)
Ltac prove_semax_prog_linked :=
  match goal with
  | |- semax_prog ?prog ?z ?Vprog ?Gprog =>
      let pr := eval unfold prog in prog in
      let x := old_with_library' pr Gprog in
      change (SeparationLogicAsLogicSoundness.MainTheorem.CSHL_MinimumLogic.CSHL_Defs.semax_prog
                prog z Vprog x)
  end;
  split3; [ | | split3; [ | | split]];
  [ fast_Qed_reflexivity || fail "duplicate identifier in prog_defs"
  | fast_Qed_reflexivity || fail "unaligned initializer"
  | reflexivity || fail "comp_specs not equal"
  |
  | fast_Qed_reflexivity || fail "match_globvars failed"
  | match goal with
    | |- match initial_world.find_id (prog_main ?prog) ?Gprog with _ => _ end =>
        unfold prog at 1; (rewrite extract_prog_main || rewrite extract_prog_main');
        ((hnf; eexists;
          try match goal with
              | |- snd ?A = _ => let j := fresh in set (j := A); hnf in j; subst j; unfold snd at 1
              end;
          try (unfold NDmk_funspec'; rewrite_old_main_pre); reflexivity)
         || fail "Funspec of _main is not in the proper form")
    end ];
  match goal with
  | |- semax_func ?V ?G ?g ?D ?G' =>
      let Gp := fresh "Gprog" in
      pose (Gp := @abbreviate _ G);
      change (semax_func V Gp g D G')
  end;
  prove_semax_prog_setup_globalenv;
  finish_semax_prog.

Lemma prog_correct : semax_prog linked_prog main_itree Vprog Gprog.
Proof.
  prove_semax_prog_linked.
  (* The order is the linked program's definition order, which [link_progs]
     sorts by identifier. *)
  semax_func_cons body_fib.
  semax_func_cons body_main.
  semax_func_cons_ext.
  { simpl; Intro i. apply typecheck_return_value with (t := Xint16signed); auto. }
  semax_func_cons_ext.
  { simpl; Intro i2. apply typecheck_return_value with (t := Xint16signed); auto. }
  semax_func_cons body_read_ulong.
  semax_func_cons body_print_ulong.
  semax_func_cons body_print_ulong_aux.
  semax_func_cons body_getchar_blocking.
  semax_func_cons body_putchar_blocking.
Qed.

(** * The end-to-end theorem

    [prog_correct] is a statement in the separation logic.  This section
    converts it into a statement about CompCert's operational semantics for
    the linked program: starting from the initial memory, the program runs
    safely for any number of steps in an environment where [getchar] and
    [putchar] behave according to [io_dry_spec] -- and [io_dry_spec] is
    stated directly on the interaction tree, so "runs safely against
    [main_itree]" is exactly "reads a decimal numeral n and writes the
    base-10 representation of fib(n) mod 2^64, followed by a newline".

    [ec_mem_sub] (VST calls it [Jsub]) says CompCert external calls are
    monotone in the memory they are given.  VST's soundness pipeline needs
    it and does not prove it; VST's own [progs64/verif_io.v] simply declares
    it as an [Axiom].  We instead take it as an explicit hypothesis, so that
    this development introduces no axioms of its own -- see [make audit]. *)


Theorem prog_prints_fib :
  ec_mem_sub ->
  forall m, Genv.init_mem linked_prog = Some m ->
  exists b q,
    Genv.find_symbol (Genv.globalenv linked_prog) (AST.prog_main linked_prog) = Some b /\
    semantics.initial_core (Clight_core.cl_core_sem (globalenv linked_prog))
      0 m q m (Vptr b Ptrofs.zero) nil /\
    forall n,
      @step_lemmas.dry_safeN _ _ _ _ semax.genv_symb_injective
        (Clight_core.cl_core_sem (globalenv linked_prog))
        (io_dry_spec ext_link)
        {| genv_genv := Genv.globalenv linked_prog;
           genv_cenv := prog_comp_env linked_prog |}
        n main_itree q m.
Proof.
  intros Jsub m Hm.
  edestruct whole_program_sequential_safety_ext with (V := Vprog) as (b & q & Hb & Hq & Hsafe).
  - repeat intro; hnf. apply I.
  - apply Jsub.
  - apply add_funspecs_frame.
  - apply juicy_dry_specs.
  - apply dry_spec_mem.
  - intros; apply I.
  - apply CSHL_Sound.semax_prog_sound, prog_correct.
  - apply Hm.
  - exists b, q; auto.
Qed.
