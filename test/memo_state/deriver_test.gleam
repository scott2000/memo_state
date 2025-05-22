import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import gleeunit/should
import memo_state/deriver.{type Deriver}
import memo_state/memo

type Changed {
  Changed
}

type Person {
  Person(name: String, age: Int)
}

type Computed {
  Computed(squared: List(Int), doubled: List(Int))
}

fn record_changed(deriver: Deriver(a, b, Changed)) -> Deriver(a, b, Changed) {
  deriver |> deriver.add_effect(deriver.effect(fn(_) { Changed }))
}

pub fn new_test() {
  let length_deriver: Deriver(String, Int, Nil) = deriver.new(string.length)

  let memo = memo.from_deriver(length_deriver, "ABC")
  memo.computed(memo) |> should.equal(3)

  let memo = memo.set_state(memo, "ABC")
  memo.computed(memo) |> should.equal(3)

  let memo = memo.set_state(memo, "ABCDEF")
  memo.computed(memo) |> should.equal(6)
}

pub fn new_with_effect_test() {
  let length_deriver: Deriver(String, Int, List(String)) =
    deriver.new_with_effect(fn(str) {
      #(string.length(str), ["Computing length of " <> str])
    })

  let #(memo, effect) =
    memo.from_deriver_with_effect(length_deriver, "ABC", list.flatten)
  effect |> should.equal(["Computing length of ABC"])
  memo.computed(memo) |> should.equal(3)

  let #(memo, effect) = memo.set_state_with_effect(memo, "ABC")
  effect |> should.equal([])
  memo.computed(memo) |> should.equal(3)

  let #(memo, effect) = memo.set_state_with_effect(memo, "ABCDEF")
  effect |> should.equal(["Computing length of ABCDEF"])
  memo.computed(memo) |> should.equal(6)
}

pub fn effect_test() {
  let effect_deriver: Deriver(String, Nil, List(String)) =
    deriver.effect(fn(str) { ["Input changed: " <> str] })

  let #(memo, effect) =
    memo.from_deriver_with_effect(effect_deriver, "ABC", list.flatten)
  effect |> should.equal(["Input changed: ABC"])

  let #(memo, effect) = memo.set_state_with_effect(memo, "ABC")
  effect |> should.equal([])

  let #(_memo, effect) = memo.set_state_with_effect(memo, "ABCDEF")
  effect |> should.equal(["Input changed: ABCDEF"])
}

pub fn selecting_test() {
  let deriver: Deriver(Person, String, Changed) =
    deriver.selecting(
      fn(person: Person) { person.name },
      deriver.new(string.uppercase) |> record_changed,
    )

  let assert #(deriver, "KEERTHY", [Changed]) =
    deriver.run(deriver, Person(name: "Keerthy", age: 24))

  let assert #(deriver, "KEERTHY", []) =
    deriver.run(deriver, Person(name: "Keerthy", age: 25))

  let assert #(_deriver, "SCOTT", [Changed]) =
    deriver.run(deriver, Person(name: "Scott", age: 25))

  Nil
}

pub fn map_test() {
  let deriver: Deriver(String, Person, Changed) =
    deriver.new(string.uppercase)
    |> record_changed
    |> deriver.map(fn(name) { Person(name:, age: 25) })

  let assert #(deriver, Person(name: "KEERTHY", age: 25), [Changed]) =
    deriver.run(deriver, "Keerthy")

  let assert #(deriver, Person(name: "KEERTHY", age: 25), []) =
    deriver.run(deriver, "Keerthy")

  let assert #(_deriver, Person(name: "SCOTT", age: 25), [Changed]) =
    deriver.run(deriver, "Scott")

  Nil
}

pub fn map2_test() {
  let deriver: Deriver(String, #(String, Int), Changed) =
    deriver.map2(
      deriver.new(string.uppercase)
        |> record_changed,
      deriver.new(string.length)
        |> record_changed,
      pair.new,
    )

  let assert #(deriver, #("WIBBLE", 6), [Changed, Changed]) =
    deriver.run(deriver, "Wibble")

  let assert #(deriver, #("WIBBLE", 6), []) = deriver.run(deriver, "Wibble")

  let assert #(_deriver, #("WOBBLE", 6), [Changed, Changed]) =
    deriver.run(deriver, "Wobble")

  Nil
}

pub fn chain_test() {
  let deriver: Deriver(Int, Int, Changed) =
    deriver.new(fn(x) { x * x })
    |> record_changed
    |> deriver.chain(deriver.new(fn(x) { x - 1 }) |> record_changed)

  let assert #(deriver, 63, [Changed, Changed]) = deriver.run(deriver, 8)

  let assert #(deriver, 63, []) = deriver.run(deriver, 8)

  let assert #(deriver, 63, [Changed]) = deriver.run(deriver, -8)

  let assert #(_deriver, 24, [Changed, Changed]) = deriver.run(deriver, 5)

  Nil
}

pub fn chain_effect_test() {
  let deriver: Deriver(String, Int, String) =
    deriver.new(string.length)
    |> deriver.chain_effect(
      deriver.effect(fn(length) { "Length is " <> int.to_string(length) }),
    )

  let assert #(deriver, 3, ["Length is 3"]) = deriver.run(deriver, "ABC")

  let assert #(deriver, 3, []) = deriver.run(deriver, "DEF")

  let assert #(_deriver, 6, ["Length is 6"]) = deriver.run(deriver, "ABCDEF")

  Nil
}

pub fn add_deriver_test() {
  let deriver: Deriver(List(Int), Computed, Nil) =
    deriver.deriving({
      use squared <- deriver.parameter
      use doubled <- deriver.parameter
      Computed(squared:, doubled:)
    })
    |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * x })))
    |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * 2 })))

  let assert #(_deriver, output, []) = deriver.run(deriver, [1, 2, 3])
  output |> should.equal(Computed(squared: [1, 4, 9], doubled: [2, 4, 6]))
}

pub fn add_effect_test() {
  let deriver: Deriver(List(Int), Computed, String) =
    deriver.deriving({
      use squared <- deriver.parameter
      use doubled <- deriver.parameter
      Computed(squared:, doubled:)
    })
    |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * x })))
    |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * 2 })))
    |> deriver.add_effect(deriver.selecting(
      fn(list) { result.unwrap(list.first(list), 0) },
      deriver.effect(fn(first) { "First element: " <> int.to_string(first) }),
    ))

  let #(deriver, output, effects) = deriver.run(deriver, [1, 2, 3])
  effects |> should.equal(["First element: 1"])
  output |> should.equal(Computed(squared: [1, 4, 9], doubled: [2, 4, 6]))

  let #(deriver, output, effects) = deriver.run(deriver, [1, 2, 4, 8])
  effects |> should.equal([])
  output
  |> should.equal(Computed(squared: [1, 4, 16, 64], doubled: [2, 4, 8, 16]))

  let #(_deriver, output, effects) = deriver.run(deriver, [5])
  effects |> should.equal(["First element: 5"])
  output
  |> should.equal(Computed(squared: [25], doubled: [10]))
}
