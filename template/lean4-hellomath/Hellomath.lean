import Mathlib.NumberTheory.Real.Irrational
import Mathlib.Tactic.NormNum

/-- Two plus two is four. -/
theorem two_plus_two : (2 : ℕ) + 2 = 4 := by norm_num

/-- The square root of two is irrational. -/
theorem sqrt_two_irrational : Irrational (Real.sqrt 2) :=
  irrational_sqrt_two
