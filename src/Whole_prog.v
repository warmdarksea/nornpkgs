(** * The linked program.

    [fib.c] and [main.c] are separate translation units; this file links their
    Clight ASTs into the single [Clight.program] that the end-to-end theorem
    talks about, and fixes the external specification.

    VST's [link_progs] is used rather than CompCert's own
    [Ctypes.link_program] because the latter does not reduce: its [Linker]
    instance bottoms out in opaque proof terms, so [vm_compute] gets stuck on
    [Linking.link fib.prog main.prog].  [link_progs] is VST's computable
    Clight linker, written for exactly this purpose. *)

Require Import VST.floyd.proofauto.
Require Import VST.floyd.linking.
Require Import VST.progs64.io_specs.
Require FibVST.fib.
Require FibVST.main.

Definition linked_prog : Clight.program := ltac:(
  let p := constr:(link_progs_list [FibVST.fib.prog; FibVST.main.prog]) in
  let p := eval vm_compute in p in
  match p with
  | Errors.OK ?q => exact q
  | Errors.Error _ => fail 1 "link_progs failed"
  end).

#[export] Instance CompSpecs : compspecs. make_compspecs linked_prog. Defined.
Definition Vprog : varspecs. mk_varspecs linked_prog. Defined.

(** [ext_link] maps an external function's name to its Clight identifier.
    clightgen's default [-canonical-idents] derives identifiers from the name
    string, so this agrees with either translation unit's own table -- which
    is also why the two units' ASTs are guaranteed to agree on every shared
    identifier without any extra side condition. *)
Definition ext_link := ext_link_prog linked_prog.

(** The external specification: [putchar] and [getchar] behave as
    [VST.progs64.io_specs] says.  This is built by [add_funspecs], not
    axiomatised -- see [IO_specs] / [IO_Espec] there. *)
#[export] Instance Espec : OracleKind := IO_Espec ext_link.
