import gleam/list
import gleam/option.{None, Some}
import gleam/pair
import gleam/string
import memo_state/deriver
import memo_state/memo

type Computed {
  Computed(uppercased: String, lowercased: String, length: #(Int, Int))
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
      pair.first,
      deriver.new_with_effect(fn(s) { #(string.uppercase(s), ["Uppercased"]) }),
    ))
    |> deriver.add_deriver(deriver.selecting(
      pair.second,
      deriver.new_with_effect(fn(s) {
        #(string.lowercase(option.unwrap(s, "")), ["Lowercased"])
      }),
    ))
    |> deriver.add_deriver(
      deriver.new_with_effect(fn(pair) {
        let #(a, b) = pair
        #(#(string.length(a), string.length(option.unwrap(b, ""))), ["Length"])
      }),
    )
    |> memo.from_deriver_with_effect(#("Test", Some("String")), list.flatten)
  let some_string = Some("String")
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, #("Test", Some("String")))
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, #("Other", some_string))
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, #("Other", some_string))
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, #("Other", None))
  echo #(memo.computed(memo), e)
  let #(memo, e) = memo.set_state_with_effect(memo, #("Same", None))
  echo #(memo.computed(memo), e)
  Nil
}
