import Mathlib.NumberTheory.Real.Irrational
import Mathlib.Tactic.NormNum
import Mathlib.Util.AssertNoSorry

/-- Two plus two is four. -/
theorem two_plus_two : (2 : ℕ) + 2 = 4 := by norm_num

/-- The square root of two is irrational. -/
theorem sqrt_two_irrational : Irrational (Real.sqrt 2) :=
  irrational_sqrt_two

-- `lake build` only *warns* about a proof left as `sorry`, so the warning is
-- easy to miss and `make test` would still pass. These make it an error:
-- `assert_no_sorry` fails elaboration if the theorem's axiom set contains
-- `sorryAx`, which is what an admitted proof shows up as.
assert_no_sorry two_plus_two
assert_no_sorry sqrt_two_irrational
