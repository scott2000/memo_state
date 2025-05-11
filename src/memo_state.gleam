import gleam/list
import gleam/result
import gleam/string
import memo_state/deriver
import memo_state/memo

type Computed {
  Computed(uppercased: String, lowercased: String, length: Int)
}

pub fn main() -> Nil {
  let #(memo, e) =
    deriver.deriving({
      use uppercased <- deriver.parameter
      use lowercased <- deriver.parameter
      use length <- deriver.parameter
      Computed(uppercased:, lowercased:, length:)
    })
    |> deriver.add_deriver(deriver.selecting(
      fn(s) { s |> string.split(" ") |> list.first |> result.unwrap("") },
      deriver.new_with_effect(fn(s) { #(string.uppercase(s), ["Uppercased"]) }),
    ))
    |> deriver.add_deriver(deriver.selecting(
      fn(s) { s |> string.split(" ") |> list.last |> result.unwrap("") },
      deriver.new_with_effect(fn(s) { #(string.lowercase(s), ["Lowercased"]) }),
    ))
    |> deriver.add_deriver(deriver.new(string.length))
    |> memo.from_deriver_with_effect("Test String", list.flatten)
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, "Test String")
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, "Other String")
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, "Other String")
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, "Other Word")
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, "Same")
  echo #(memo.computed(memo), e)
  Nil
}
