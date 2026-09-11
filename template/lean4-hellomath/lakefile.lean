import Lake
open Lake DSL

package «lean4-hellomath»

-- Provided by nix (leanPackages.mathlib) via buildLakePackage's leanDeps;
-- never fetched or built by lake itself.
require "leanprover-community" / "mathlib" @ git "main"

@[default_target]
lean_lib Hellomath
