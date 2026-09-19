# An end-to-end verified Fibonacci program (VST / CompCert template)

A small, complete, **admit-free** Verified Software Toolchain project, meant to be
copied as the starting point for other verified-C work. Two C translation units,
two theorems, a Makefile, and a Nix flake that pins everything.

The program reads a decimal number from stdin and prints its Fibonacci number in
base 10:

```console
$ echo 90 | ./build/fib
2880067194370816120
```

## What is proved

**Proof 1 — `fib.c` computes the Fibonacci function** (`src/Verif_fib.v`):

```coq
Lemma body_fib : semax_body Vprog Gprog f_fib fib_spec.
```

where `fib_spec` (`src/Fib_spec.v`) requires only `0 <= n <= Int64.max_unsigned`
and promises `Int64.repr (fib (Z.to_nat n))` — i.e. the mathematical Fibonacci
number truncated to 64 bits, over the *entire* range of `unsigned long`. There is
no input on which the function may misbehave. `Fib_model.fib_mod_eq` restates the
truncation as `fib n mod 2^64` if you prefer to read it that way.

**Proof 2 — the linked program prints it** (`src/Link.v`):

```coq
Lemma prog_correct : semax_prog linked_prog main_itree Vprog Gprog.

Theorem prog_prints_fib :
  ec_mem_sub ->
  forall m, Genv.init_mem linked_prog = Some m ->
  exists b q, ... /\ forall n, dry_safeN ... (io_dry_spec ext_link) ... n main_itree q m.
```

The observable behaviour lives in `main_itree` (`src/IO_model.v`), which *is* the
specification:

```coq
Definition main_itree : IO_itree :=
  n <- read_num ;;
  write_list stdout (chars_of_Z (fib_mod n)) ;;
  write stdout (Byte.repr newline).
```

`chars_of_Z` is the base-10 rendering function, so "prints the base-10
representation of fib(n) mod 2^64" is definitional rather than an extra
obligation. `read_num` accumulates digits modulo 2^64 exactly as the C does.
`prog_correct` is the separation-logic statement; `prog_prints_fib` converts it
into a statement about CompCert's operational semantics for the linked program.

### What the proofs rest on

`make audit` prints `Print Assumptions` for all three theorems and fails if
anything from this development's own namespace shows up (which is how an
`Admitted` lemma manifests). What remains is:

| axiom | whose |
| --- | --- |
| `prop_ext`, `proof_irr`, `functional_extensionality_dep`, `classic`, `eq_rect_eq`, `Extensionality_Ensembles`, `ClassicalDedekindReals.*` | classical logic; VST is built on these |
| `Events.external_functions_sem`, `Events.inline_assembly_sem` | CompCert's parameters for unspecified external functions |
| `Clight_core.inline_external_call_mem_events` | VST's own |

`ec_mem_sub` (VST calls it `Jsub`) says CompCert external calls are monotone in
the memory they are given. VST's soundness pipeline needs it and does not prove
it — VST's own `progs64/verif_io.v` declares it as a local `Axiom`. Here it is an
explicit **hypothesis** of `prog_prints_fib`, so this development introduces no
axioms of its own.

## Two things the toolchain forces

Worth knowing before you adapt this template, because both surprised us:

1. **`main` must be `int main(void)`.** CompCert's `Clight.initial_state`
   requires `type_of_fundef f = Tfunction nil type_int32s cc_default`
   (`compcert/cfrontend/Clight.v`), and VST's `main_spec_ext'` hardcodes typesig
   `(nil, tint)` while `main_pre` asserts the argument list is empty. There is not
   one mention of `argc` or `argv` in all of VST. An `argv`-taking `main` has no
   CompCert semantics at all, so no whole-program theorem about one is possible.
   That is why the input arrives on stdin.

2. **`VST/floyd/printf.v` is not usable for this.** It understands only `%d`,
   `%s` and `%%` — `%ld` becomes `FI_error`, whose precondition is `PROP(False)`,
   so a 64-bit value cannot be printed through it. More seriously it rests on
   `Axiom printf_spec_sub`, which asserts `funspec_sub` between two funspecs whose
   typesigs differ structurally; since `funspec_sub` requires `tpsig1 = tpsig2`,
   that axiom is false and anything proved with it is vacuous. So the decimal
   rendering is done by verified C here (`print_ulong`), on top of VST's
   axiom-free `putchar`/`getchar` interaction-tree specs
   (`VST/progs64/io_specs.v`). The same goes for the parse: `read_ulong` is a
   verified `atol`. Both are *more* than the original sketch proved, since libc's
   conversions are no longer trusted.

## Layout

```
flake.nix            pinned toolchain, package, checks, devshell
Makefile             clightgen + ccomp + coqc, all output into build/
src/fib.h
src/fib.c            the unit under proof 1
src/main.c           the unit under proof 2
src/Fib_model.v      pure Coq: the Fibonacci function. No VST.
src/IO_model.v       the interaction tree: what the program must read and print
src/Fib_spec.v       fib.c's exported interface (its funspec)
src/Whole_prog.v     the two ASTs linked; compspecs, varspecs, external spec
src/Main_spec.v      the remaining funspecs, and Gprog
src/Verif_fib.v      PROOF 1
src/Verif_main.v     the six body proofs for main.c
src/Link.v           PROOF 2: semax_prog, and whole-program safety
build/               fib.v main.v *.o fib *.vo *.glob assumptions.txt
```

Dependencies flow strictly downwards. The proof script in `Verif_fib.v` mentions
nothing from `main.c` — it refers to the shared `Vprog`/`Gprog` only because VST
states `semax_body` relative to an ambient context — and `Verif_main.v` never
mentions `f_fib`: `main`'s proof reaches `fib` only through `fib_spec`. That is
the sense in which the two compilation units are verified separately.

## Building

```console
$ nix develop          # coqc, clightgen, ccomp, VST, CompCert, ITree on PATH
$ make                 # ~25 s from clean: clightgen, ccomp, and every proof
$ make audit           # what the theorems depend on; fails on any admit
$ make smoke           # run the binary against values computed from the Coq model
$ make _CoqProject     # for your editor; the Makefile itself uses COQPATH
```

Or without entering the shell:

```console
$ nix build            # the ccomp-built binary, at ./result/bin/fib
$ nix flake check      # clightgen + all proofs + audit + smoke tests, sandboxed
```

The binary is built with **`ccomp`**, not gcc: the theorems are about CompCert's
semantics of these sources, so compiling them with the verified compiler is what
keeps the chain meaningful.

## Notes for adapting this

- **clightgen must see both `.c` files in one invocation.** `-o` is rejected for
  multiple inputs, and a single invocation guarantees the two units share builtin
  tables and composite environments, which linking requires. `-normalize` is
  mandatory; floyd's `forward` tactics reject un-normalized ASTs. The default
  `-canonical-idents` derives identifiers from the name string, so the two units
  agree on every shared identifier with no extra side condition.
- **Build artifacts in `build/`** work because `coqc` derives a file's logical
  name from its `-o` path against the load path: `coqc -Q build FibVST -o
  build/X.vo src/X.v` compiles `src/X.v` as `FibVST.X`. `coqdep`'s output is
  rewritten by one `sed` in the Makefile.
- **Linking** uses VST's `link_progs` (`VST/floyd/linking.v`). CompCert's own
  `Ctypes.link_program` does not reduce — its `Linker` instance bottoms out in
  opaque proof terms, so `vm_compute` gets stuck on
  `Linking.link fib.prog main.prog`. The linked program is `vm_compute`d at
  definition time, because VST's `prove_semax_prog` needs `prog_defs` in reduced
  form.
- **`prove_semax_prog` needs one tweak for a linked program** (`src/Link.v`):
  its compspecs step, `solve_cenvcs_goal`, pattern-matches on the program being a
  `Clightdefs.mkprogram`, which a linked program is not. Plain `reflexivity` does
  it here, since neither unit declares a struct or union. The same applies to
  `expand_main_pre`, which `Verif_main.body_main` therefore does by hand.
- **VST 2.16 is the classic, pre-Iris line.** `mpred = pred rmap`; use `sepcon`,
  `entailer!`, `|--`, not the Iris proof mode. `VST/veric/bi.v` ships unbuilt.
- **`VST/progs64/io_specs.v` ships source-only** (upstream's Makefile gates the
  ITree-dependent files), so `flake.nix` defines a small `vst-io` derivation that
  compiles it — along with `dry_mem_lemmas.v` and `io_dry.v` — into VST's own
  namespace. Nothing is vendored into this repo.
- **CompCert is unfree** (INRIA non-commercial), so the flake sets
  `config.allowUnfree = true`.

`src/Verif_main.v` borrows `body_getchar_blocking` and `body_putchar_blocking`
verbatim from VST's `progs64/verif_io.v`, and `body_print_ulong_aux` follows its
`body_print_intr` at 64 bits; `src/IO_model.v` reuses its `chars_of_Z` / `intr`
and the `Program Fixpoint` unfolding machinery. VST is BSD-licensed; see
`VST/LICENSE` in the store path the flake pins.
