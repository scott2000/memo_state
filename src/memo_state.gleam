import cat/instances/monoid
import gleam/list
import gleam/result
import gleam/string
import memo_state/deriver

type Computed {
  Computed(uppercased: String, lowercased: String, length: Int)
}

pub fn main() -> Nil {
  let d =
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
    |> deriver.add_deriver(deriver.simple(string.length))
    |> deriver.finish(monoid.list_monoid())
  let #(d, s, e) = deriver.update(d, "Test string")
  echo #(s, e)
  let #(d, s, e) = deriver.update(d, "Test string")
  echo #(s, e)
  let #(d, s, e) = deriver.update(d, "Other string")
  echo #(s, e)
  let #(d, s, e) = deriver.update(d, "Other string")
  echo #(s, e)
  let #(d, s, e) = deriver.update(d, "Other word")
  echo #(s, e)
  let #(_, s, e) = deriver.update(d, "Same")
  echo #(s, e)
  Nil
}
