import Lake
open Lake DSL

package «lean4-hello»

@[default_target]
lean_exe «lean4-hello» where
  root := `Main
