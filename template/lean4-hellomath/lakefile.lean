import Lake
open Lake DSL

package «lean4-hellomath»

-- Provided by nix (leanPackages.mathlib) via buildLakePackage's leanDeps;
-- never fetched or built by lake itself.
require "leanprover-community" / "mathlib" @ git "main"

-- The proofs. Building this library is what type-checks them.
@[default_target]
lean_lib Hellomath

-- A Mathlib-free hello world, so the template has something to run. See the
-- comment at the top of Main.lean for why it cannot import Hellomath.
@[default_target]
lean_exe «lean4-hellomath» where
  root := `Main
