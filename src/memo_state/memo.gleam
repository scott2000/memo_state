//// This module provides a high-level interface for dealing with memoized data
//// and effects through the `Memo` type.

import gleam/bool
import gleam/pair
import memo_state/deriver.{type Deriver}

/// A `Memo` contains a current state value and a computed value based on that
/// state. If the state changes, the computed value is updated automatically.
/// It is also possible to return an effect when the state changes using the
/// `effect` type variable. If no effect is needed, this can just be `Nil`.
pub opaque type Memo(state, computed, effect) {
  Memo(
    state: state,
    computed: computed,
    batch_effects: fn(List(effect)) -> effect,
    deriver: Deriver(state, computed, effect),
  )
}

/// Create a `Memo` based on an initial state and a function to compute.
/// This is a shorthand for `deriver.new(compute) |> memo.from_deriver(state)`.
///
/// # Examples
///
/// ```gleam
/// let memo = memo.new(0, fn(x) { x * x })
/// memo.state(memo)    // -> 0
/// memo.computed(memo) // -> 0
///
/// let memo = memo.set_state(memo, 12)
/// memo.state(memo)    // -> 12
/// memo.computed(memo) // -> 144
///
/// let memo = memo.update(memo, int.divide(_, 2))
/// memo.state(memo)    // -> 6
/// memo.computed(memo) // -> 36
/// ```
pub fn new(initial_state: a, compute: fn(a) -> b) -> Memo(a, b, Nil) {
  deriver.new(compute)
  |> from_deriver(initial_state)
}

/// Create a `Memo` based on a deriver. Derivers allow combining multiple
/// computations together, with each computation cached separately. See the
/// `memo_state/deriver` module for more information.
///
/// # Examples
///
/// ```gleam
/// let full_name_deriver: Deriver(Person, String, Nil) =
///   deriver.selecting(
///     fn(person: Person) { #(person.first_name, person.last_name) },
///     deriver.new(fn(args) {
///       let #(first_name, last_name) = args
///       echo "Recomputing full name..."
///       first_name <> " "<> last_name
///     }),
///   )
///
/// let initial_person = Person(
///   first_name: "Keerthy",
///   last_name: "Sudharsan",
///   age: 24,
/// )
///
/// // Prints "Recomputing full name..."
/// let memo = memo.from_deriver(full_name_deriver, initial_person)
/// memo.computed(memo) // -> "KEERTHY SUDHARSAN"
///
/// // Doesn't print anything since result is cached
/// let memo = memo.update(memo, fn(p) { Person(..p, age: 25) })
/// memo.computed(memo) // -> "KEERTHY SUDHARSAN"
///
/// // Prints "Recomputing full name..."
/// let memo = memo.update(memo, fn(p) { Person(..p, first_name: "Scott") })
/// memo.computed(memo) // -> "SCOTT SUDHARSAN"
/// ```
pub fn from_deriver(
  deriver: Deriver(a, b, Nil),
  initial_state: a,
) -> Memo(a, b, Nil) {
  deriver
  |> from_deriver_with_effect(initial_state, fn(_) { Nil })
  |> pair.first
}

/// Create a `Memo` based on a deriver which can return an effect value. See
/// the `memo_state/deriver` module for more information.
///
/// The most common use-case for this type of `Memo` is to produce effects in
/// a `lustre` update function, but there are no restrictions on what value can
/// be used as an "effect".
pub fn from_deriver_with_effect(
  deriver: Deriver(a, b, c),
  initial_state: a,
  batch_effects: fn(List(c)) -> c,
) -> #(Memo(a, b, c), c) {
  let #(deriver, computed, effects) =
    deriver
    |> deriver.run(initial_state)
  #(
    Memo(state: initial_state, computed:, batch_effects:, deriver:),
    batch_effects(effects),
  )
}

/// Update the state of this `Memo` by mapping the state using a function. The
/// computed value will also be updated automatically if the state changed.
///
/// # Examples
///
/// ```gleam
/// let memo = memo.new(5, int.multiply(_, 2))
/// memo.state(memo)    // -> 5
/// memo.computed(memo) // -> 10
///
/// let memo = memo.update(memo, int.add(_, 1))
/// memo.state(memo)    // -> 6
/// memo.computed(memo) // -> 12
/// ```
pub fn update(memo: Memo(a, b, Nil), f: fn(a) -> a) -> Memo(a, b, Nil) {
  set_state(memo, f(memo.state))
}

/// Similar to `memo.update`, but allows both the update function and the
/// deriver to return effects. See the `memo_state/deriver` module for examples
/// of derivers with effects. This must be used instead of `memo.update` if the
/// `Memo` was created with `memo.from_deriver_with_effect`.
pub fn update_with_effect(
  memo: Memo(a, b, c),
  f: fn(a) -> #(a, c),
) -> #(Memo(a, b, c), c) {
  let #(new_state, update_effect) = f(memo.state)
  use <- bool.guard(when: fast_equals(new_state, memo.state), return: #(
    memo,
    update_effect,
  ))
  let #(deriver, computed, effects) = deriver.run(memo.deriver, new_state)
  let effect = memo.batch_effects([update_effect, ..effects])
  #(Memo(..memo, state: new_state, computed:, deriver:), effect)
}

/// Set the state of this `Memo`. The computed value will also be updated
/// automatically if the state changed.
///
/// # Examples
///
/// ```gleam
/// let memo = memo.new(5, int.multiply(_, 2))
/// memo.state(memo)    // -> 5
/// memo.computed(memo) // -> 10
///
/// let memo = memo.set_state(memo, 6)
/// memo.state(memo)    // -> 6
/// memo.computed(memo) // -> 12
/// ```
pub fn set_state(memo: Memo(a, b, Nil), new_state: a) -> Memo(a, b, Nil) {
  use <- bool.guard(when: fast_equals(new_state, memo.state), return: memo)
  let #(deriver, computed, _effects) = deriver.run(memo.deriver, new_state)
  Memo(..memo, state: new_state, computed:, deriver:)
}

/// Similar to `memo.set_state`, but allows the deriver to return effects. See
/// the `memo_state/deriver` module for examples of derivers with effects. This
/// must be used instead of `memo.set_state` if the `Memo` was created with
/// `memo.from_deriver_with_effect`.
pub fn set_state_with_effect(
  memo: Memo(a, b, c),
  new_state: a,
) -> #(Memo(a, b, c), c) {
  use <- bool.lazy_guard(when: fast_equals(new_state, memo.state), return: fn() {
    #(memo, memo.batch_effects([]))
  })
  let #(deriver, computed, effects) = deriver.run(memo.deriver, new_state)
  #(
    Memo(..memo, state: new_state, computed:, deriver:),
    memo.batch_effects(effects),
  )
}

/// Get the current state of a `Memo`.
pub fn state(memo: Memo(a, b, c)) -> a {
  memo.state
}

/// Get the current computed value of a `Memo`.
pub fn computed(memo: Memo(a, b, c)) -> b {
  memo.computed
}

@external(javascript, "./deriver.ffi.mjs", "shallowEquals")
fn fast_equals(_a: a, _b: a) -> Bool {
  False
}
