# lean 4 + mathlib template

Proofs in `Hellomath.lean`, checked by nix:

```console
$ make test
type-checked: Hellomath
type-checked: Main
lean4-hellomath: proofs type-checked, no sorry ✓

$ make run
hello, world!
the proofs in Hellomath.lean type-checked during this build.
```

`make build` is the whole thing: in lean the build *is* the typecheck, so a
proof that does not go through is a build failure. `make test` adds the two
checks a green build does not give you by itself:

* **no `sorry`.** `lake build` only *warns* about an admitted proof, and the
  warning is easy to lose in the log. `Hellomath.lean` ends in
  `assert_no_sorry` lines (from `Mathlib.Util.AssertNoSorry`), which fail
  elaboration if the theorem's axiom set contains `sorryAx`.
* **no module left behind.** It checks that every `.lean` file in the project
  produced an olean, so a module missing from `lakefile.lean`'s targets cannot
  pass unnoticed.

Mathlib comes from `leanPackages.mathlib` in nixpkgs, via `buildLakePackage`'s
`leanDeps`; lake never fetches or builds it. The first build is cheap if your
substituter has it and very expensive if it does not.

## why `Main.lean` does not import `Hellomath`

nixpkgs' `leanPackages.mathlib` installs the olean tree and the generated C,
but no `.o` or `.a` objects. So Mathlib can be *imported* (typechecking only
needs oleans) but nothing can be *linked* against it: an executable whose
transitive imports reach Mathlib makes lake try to compile all ~8000 of those
C files, in place, inside the read-only mathlib store path:

```
Fatal error: can't create /nix/store/...-lean4-mathlib-4.30.0/.lake/build/ir/Mathlib/Logic/Unique.c.o.export: Permission denied
```

`Main.lean` is therefore a Mathlib-free executable, so the template has
something for `make run` to run. The proofs are type-checked in the same
derivation that links it — `lake build` builds both default targets — so a
binary existing does mean the proofs went through.

If you need a binary that genuinely calls into Mathlib, nixpkgs' packaging is
not enough: build Mathlib yourself with `precompileModules := true` (which
emits the shared objects), or keep the computational core Mathlib-free and use
Mathlib only to prove things *about* it.

## layout

| file | |
| --- | --- |
| `Hellomath.lean` | the proofs, and the `assert_no_sorry` guards |
| `Main.lean` | the Mathlib-free executable `make run` runs |
| `lakefile.lean` | `lean_lib Hellomath` + `lean_exe lean4-hellomath`, both default targets |
| `flake.nix` | `buildLakePackage`, with `src` filtered down to what lake needs |
| `Makefile` | ergonomics around `nix build`; `-L` keeps `make run` from re-evaluating the flake |
