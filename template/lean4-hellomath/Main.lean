/-
The executable `make run` runs.

It deliberately does not `import Hellomath`: nixpkgs' `leanPackages.mathlib`
installs oleans and the C IR, but no `.o`/`.a` objects, so lake has nothing to
link an executable against. Importing a Mathlib-using module here makes lake
try to compile all ~8000 of Mathlib's generated C files into the (read-only)
mathlib store path, which fails on the first one. Proofs are type-checked, not
linked -- that is what `make test` covers.
-/

def main : IO Unit := do
  IO.println "hello, world!"
  IO.println "the proofs in Hellomath.lean type-checked during this build."
