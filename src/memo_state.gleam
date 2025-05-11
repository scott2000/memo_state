import cat/instances/monoid
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
      deriver.new(fn(s) { #(string.uppercase(s), ["Uppercased"]) }),
    ))
    |> deriver.add_deriver(deriver.selecting(
      fn(s) { s |> string.split(" ") |> list.last |> result.unwrap("") },
      deriver.new(fn(s) { #(string.lowercase(s), ["Lowercased"]) }),
    ))
    |> deriver.add_deriver(deriver.new_simple(string.length))
    |> memo.from_deriver("Test String", monoid.list_monoid())
  echo #(memo.get_computed(memo), e)
  let #(memo, e) = memo.set_state(memo, "Test String")
  echo #(memo.get_computed(memo), e)
  let #(memo, e) = memo.set_state(memo, "Other String")
  echo #(memo.get_computed(memo), e)
  let #(memo, e) = memo.set_state(memo, "Other String")
  echo #(memo.get_computed(memo), e)
  let #(memo, e) = memo.set_state(memo, "Other Word")
  echo #(memo.get_computed(memo), e)
  let #(memo, e) = memo.set_state(memo, "Same")
  echo #(memo.get_computed(memo), e)
  Nil
}
