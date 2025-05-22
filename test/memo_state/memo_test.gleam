import gleam/int
import gleam/list
import gleeunit/should
import memo_state/deriver.{type Deriver}
import memo_state/memo

type Changed {
  Changed
}

type Person {
  Person(first_name: String, last_name: String, age: Int)
}

pub fn new_test() {
  let memo = memo.new(0, fn(x) { x * x })
  memo.state(memo) |> should.equal(0)
  memo.computed(memo) |> should.equal(0)

  let memo = memo.set_state(memo, 6)
  memo.state(memo) |> should.equal(6)
  memo.computed(memo) |> should.equal(36)

  let memo = memo.update(memo, int.multiply(_, 2))
  memo.state(memo) |> should.equal(12)
  memo.computed(memo) |> should.equal(144)
}

pub fn from_deriver_test() {
  let full_name_deriver: Deriver(Person, String, List(Changed)) =
    deriver.selecting(
      fn(person: Person) { #(person.first_name, person.last_name) },
      deriver.new_with_effect(fn(args) {
        let #(first_name, last_name) = args
        #(first_name <> " " <> last_name, [Changed])
      }),
    )

  let initial_person =
    Person(first_name: "Keerthy", last_name: "Sudharsan", age: 24)

  let assert #(memo, [Changed]) =
    memo.from_deriver_with_effect(
      full_name_deriver,
      initial_person,
      list.flatten,
    )
  memo.computed(memo) |> should.equal("Keerthy Sudharsan")

  let assert #(memo, []) =
    memo.update_with_effect(memo, fn(p) { #(Person(..p, age: 25), []) })
  memo.computed(memo) |> should.equal("Keerthy Sudharsan")

  let assert #(memo, [Changed]) =
    memo.update_with_effect(memo, fn(p) {
      #(Person(..p, first_name: "Scott"), [])
    })
  memo.computed(memo) |> should.equal("Scott Sudharsan")
}

pub fn set_state_test() {
  let memo = memo.new(5, int.multiply(_, 2))
  memo.state(memo) |> should.equal(5)
  memo.computed(memo) |> should.equal(10)

  let memo = memo.set_state(memo, 6)
  memo.state(memo) |> should.equal(6)
  memo.computed(memo) |> should.equal(12)
}
