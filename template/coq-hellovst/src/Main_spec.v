(** * Specifications for the functions in [main.c].

    The specs for [getchar]/[putchar] and their blocking wrappers are VST's
    own ([VST.progs64.io_specs] and [VST/progs64/verif_io.v]); [main.c]
    deliberately wraps them exactly as VST's [io.c] does, so that those two
    proofs carry over unchanged.

    [Require Import VST.floyd.VSU] must come before any use of [main_pre]:
    VSU.v shadows it with the QP-program version, which is the one the
    linking machinery expects. *)

Require Import VST.floyd.proofauto.
Require Import VST.progs64.io_specs.
Require Import FibVST.main.
Require Import FibVST.Fib_spec.
Require Import FibVST.Whole_prog.
Require Import FibVST.Fib_model.
Require Import FibVST.IO_model.


Local Open Scope itree_scope.
Local Open Scope assert.

(** ** The two libc functions we depend on. *)

Definition putchar_spec := DECLARE _putchar putchar_spec.
Definition getchar_spec := DECLARE _getchar getchar_spec.

(** ** Retry wrappers: turn a possibly-failing call into a committed one. *)

Definition getchar_blocking_spec :=
 DECLARE _getchar_blocking
  WITH k : byte -> IO_itree
  PRE [ ]
    PROP ()
    PARAMS ()
    GLOBALS ()
    SEP (ITREE (r <- read stdin;; k r))
  POST [ tint ]
   EX i : byte,
    PROP ()
    LOCAL (temp ret_temp (Vubyte i))
    SEP (ITREE (k i)).

Definition putchar_blocking_spec :=
 DECLARE _putchar_blocking
  WITH c : byte, k : IO_itree
  PRE [ tint ]
    PROP ()
    PARAMS (Vubyte c)
    GLOBALS ()
    SEP (ITREE (r <- write stdout c ;; k))
  POST [ tint ]
    PROP ()
    LOCAL (temp ret_temp (Vubyte c))
    SEP (ITREE k).

(** ** Decimal input: the verified [atol]. *)

Definition read_ulong_spec :=
 DECLARE _read_ulong
  WITH k : Z -> IO_itree
  PRE [ ]
    PROP ()
    PARAMS ()
    GLOBALS ()
    SEP (ITREE (n <- read_num ;; k n))
  POST [ tulong ]
   EX n : Z,
    PROP (0 <= n < Int64.modulus)
    LOCAL (temp ret_temp (Vlong (Int64.repr n)))
    SEP (ITREE (k n)).

(** ** Decimal output: the verified ["%lu"]. *)

Definition print_ulong_aux_spec :=
 DECLARE _print_ulong_aux
  WITH i : Z, tr : IO_itree
  PRE [ tulong ]
    PROP (0 <= i <= Int64.max_unsigned)
    PARAMS (Vlong (Int64.repr i))
    GLOBALS ()
    SEP (ITREE (write_list stdout (intr i) ;; tr))
  POST [ tvoid ]
    PROP ()
    LOCAL ()
    SEP (ITREE tr).

Definition print_ulong_spec :=
 DECLARE _print_ulong
  WITH i : Z, tr : IO_itree
  PRE [ tulong ]
    PROP (0 <= i <= Int64.max_unsigned)
    PARAMS (Vlong (Int64.repr i))
    GLOBALS ()
    SEP (ITREE (write_list stdout (chars_of_Z i) ;; tr))
  POST [ tvoid ]
    PROP ()
    LOCAL ()
    SEP (ITREE tr).

(** ** main

    The entire observable behaviour of the program is the oracle
    [main_itree] threaded through [main_pre]; the postcondition only has to
    say that main returns 0. *)

Definition main_spec :=
 DECLARE _main
  WITH gv : globals
  PRE [ ]
    main_pre linked_prog main_itree gv
  POST [ tint ]
    PROP ()
    LOCAL (temp ret_temp (Vint (Int.repr 0)))
    (* Stronger than the usual [TT]: at the end of main the interaction tree
       has been consumed down to [Ret tt], i.e. the program performed exactly
       the I/O that [main_itree] prescribes -- no more, no less. *)
    SEP (ITREE done).

(** The funspec table for the linked program.  Note what is *not* here:
    [f_fib].  [main.c]'s proof sees [fib] only through [fib_spec], which is
    the interface [fib.c] exports -- that is the sense in which the two
    compilation units are verified separately. *)
Definition Gprog : funspecs :=
  [putchar_spec; getchar_spec; fib_spec;
   getchar_blocking_spec; putchar_blocking_spec;
   read_ulong_spec; print_ulong_aux_spec; print_ulong_spec;
   main_spec].
