//// This module provides a fine-grained interface for dealing with memoized
//// data and effects. The `Deriver` type represents a set of computations and
//// effects which should only be re-run whenever an input (or part of an
//// input) has changed. While derivers can be used directly using
//// `deriver.run`, usually it is better to use a `Memo` to maintain the
//// current state and computed value, ensuring they remain in sync.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}

/// A deriver represents a cached computation which produces an output and
/// optionally a list of effects. A deriver remembers its previous input value,
/// so the computation is only performed if the input changed compared to the
/// previous input. If the input did not change, the cached output is returned,
/// and no effects are returned.
///
/// For the JavaScript target, a custom shallow equality algorithm is used to
/// check for changes efficiently, but other options are available as well.
/// See `deriver.with_shallow_equality` for more details.
pub opaque type Deriver(input, output, effect) {
  Deriver(
    update: fn(input, fn(Dynamic, Dynamic) -> Bool) ->
      DeriverOutput(output, effect, Deriver(input, output, effect)),
  )
}

/// Create a deriver from a pure function. This function will only be called
/// when the input changes. This is analogous to `useMemo` in React.
///
/// # Examples
///
/// ```gleam
/// let length_deriver: Deriver(String, Int, Nil) =
///   deriver.new(fn(str) {
///     echo "Computing length of " <> str
///     string.length(str)
///   })
///
/// // Prints "Computing length of ABC"
/// let memo = memo.from_deriver(length_deriver, "ABC")
/// memo.computed(memo) // -> 3
///
/// // Doesn't print anything since result is cached
/// let memo = memo.set_state(memo, "ABC")
/// memo.computed(memo) // -> 3
///
/// // Prints "Computing length of ABCDEF"
/// let memo = memo.set_state(memo, "ABCDEF")
/// memo.computed(memo) // -> 6
/// ```
pub fn new(compute: fn(a) -> b) -> Deriver(a, b, c) {
  new_raw(fn(input) {
    let output = compute(input)
    #(output, [])
  })
}

/// Create a deriver from a function that returns an effect in addition to an
/// output value. This function will only be called when the input changes.
///
/// The most common use-case for this type of deriver is to produce effects in
/// a `lustre` update function, but there are no restrictions on what value can
/// be used as an "effect".
///
/// # Examples
///
/// ```gleam
/// let length_deriver: Deriver(String, Int, List(String)) =
///   deriver.new_with_effect(fn(str) {
///     #(string.length(str), ["Computing length of " <> str])
///   })
///
/// let #(memo, effect) =
///   memo.from_deriver_with_effect(length_deriver, "ABC", list.flatten)
/// effect              // -> ["Computing length of ABC"]
/// memo.computed(memo) // -> 3
///
/// let #(memo, effect) = memo.set_state_with_effect(memo, "ABC")
/// effect              // -> []
/// memo.computed(memo) // -> 3
///
/// let #(memo, effect) = memo.set_state_with_effect(memo, "ABCDEF")
/// effect              // -> ["Computing length of ABCDEF"]
/// memo.computed(memo) // -> 6
/// ```
pub fn new_with_effect(compute: fn(a) -> #(b, c)) -> Deriver(a, b, c) {
  new_raw(fn(input) {
    let #(output, effect) = compute(input)
    #(output, [effect])
  })
}

/// Create a deriver which only produces an effect without returning a value.
/// The effect will only be produced if the input changes. This is analogous
/// to `useEffect` in React.
///
/// The most common use-case for this type of deriver is to produce effects in
/// a `lustre` update function, but there are no restrictions on what value can
/// be used as an "effect".
///
/// # Examples
///
/// ```gleam
/// let effect_deriver: Deriver(String, Nil, List(String)) =
///   deriver.effect(fn(str) {
///     ["Input changed: " <> str]
///   })
///
/// let #(memo, effect) =
///   memo.from_deriver_with_effect(effect_deriver, "ABC", list.flatten)
/// effect // -> ["Input changed: ABC"]
///
/// let #(memo, effect) = memo.set_state_with_effect(memo, "ABC")
/// effect // -> []
///
/// let #(memo, effect) = memo.set_state_with_effect(memo, "ABCDEF")
/// effect // -> ["Computing length of ABCDEF"]
/// ```
pub fn effect(on_change: fn(a) -> b) -> Deriver(a, Nil, b) {
  new_raw(fn(input) {
    let effect = on_change(input)
    #(Nil, [effect])
  })
}

fn new_raw(compute: fn(a) -> #(b, List(c))) -> Deriver(a, b, c) {
  use input, _eq <- Deriver
  let #(output, effects) = compute(input)
  let next = new_helper(input, output, compute)
  Changed(output:, effects:, next:)
}

fn new_helper(
  prev_input: a,
  prev_output: b,
  compute: fn(a) -> #(b, List(c)),
) -> Deriver(a, b, c) {
  use input, eq <- Deriver
  case eq(dynamic.from(input), dynamic.from(prev_input)) {
    True -> Unchanged(prev_output)
    False -> {
      let #(output, effects) = compute(input)
      let next = new_helper(input, output, compute)
      Changed(output:, effects:, next:)
    }
  }
}

/// Select a value from the input before passing it to a deriver. The selection
/// function should be cheap, since it is called every time the deriver runs,
/// regardless of whether the input changed.
///
/// # Examples
///
/// ```gleam
/// let name_deriver: Deriver(Person, String, Nil) =
///   deriver.selecting(
///     fn(person: Person) { person.name },
///     deriver.new(fn(name: String) {
///       string.uppercase(name)
///     }),
///   )
///
/// let memo = memo.from_deriver(name_deriver, Person(name: "Keerthy"))
/// memo.computed(memo) // -> "KEERTHY"
/// ```
pub fn selecting(
  select: fn(a) -> b,
  deriver: Deriver(b, c, d),
) -> Deriver(a, c, d) {
  use input, eq <- Deriver
  use next <- map_next(deriver.update(select(input), eq))
  selecting(select, next)
}

/// Map the output of a deriver. The mapping function's output is cached, so it
/// will only be called if the deriver is re-computed.
///
/// # Examples
///
/// ```gleam
/// let person_deriver: Deriver(String, Person, Nil) =
///   deriver.new(string.uppercase)
///   |> deriver.map(fn(name) { Person(name:) })
///
/// let memo = memo.from_deriver(person_deriver, "Keerthy")
/// memo.computed(memo) // -> Person(name: "KEERTHY")
/// ```
pub fn map(deriver: Deriver(a, b, d), map: fn(b) -> c) -> Deriver(a, c, d) {
  map_helper(deriver, map, None)
}

fn map_helper(
  deriver: Deriver(a, b, d),
  map: fn(b) -> c,
  prev_output: Option(c),
) -> Deriver(a, c, d) {
  use input, eq <- Deriver
  use output, next <- map_with_default(
    deriver.update(input, eq),
    prev_output,
    map,
  )
  map_helper(next, map, Some(output))
}

/// Combine two derivers, calling a mapping function with the outputs of both
/// derivers. The mapping function's output is cached, so it will only be
/// called if at least one of the two derivers is re-computed.
///
/// To combine more than two derivers, see `deriver.add_deriver`.
///
/// # Examples
///
/// ```gleam
/// let pair_deriver: Deriver(String, #(String, Int), Nil) =
///   deriver.map2(
///     deriver.new(string.uppercase),
///     deriver.new(string.length),
///     pair.new,
///   )
///
/// let memo = memo.from_deriver(pair_deriver, "Wibble")
/// memo.computed(memo) // -> #("WIBBLE", 6)
/// ```
pub fn map2(
  left: Deriver(a, b, e),
  right: Deriver(a, c, e),
  map: fn(b, c) -> d,
) -> Deriver(a, d, e) {
  let mapper = fn(pair: #(b, c)) -> d { map(pair.0, pair.1) }
  map2_helper(left, right, mapper, None)
}

fn map2_helper(
  left: Deriver(a, b, e),
  right: Deriver(a, c, e),
  map: fn(#(b, c)) -> d,
  prev_output: Option(d),
) -> Deriver(a, d, e) {
  use input, eq <- Deriver
  let merged = merge_output(left.update(input, eq), right.update(input, eq))
  use output, #(next_left, next_right) <- map_with_default(
    merged,
    prev_output,
    map,
  )
  map2_helper(
    option.unwrap(next_left, left),
    option.unwrap(next_right, right),
    map,
    Some(output),
  )
}

/// Combine two derivers, passing the output of the first deriver as the input
/// of the second deriver.
///
/// # Examples
///
/// ```gleam
/// let squared_minus_one_deriver: Deriver(Int, Int, Nil) =
///   deriver.new(fn(x) { x * x })
///   |> deriver.chain(deriver.new(fn(x) { x - 1 }))
///
/// let memo = memo.from_deriver(squared_minus_one_deriver, 8)
/// memo.computed(memo) // -> 63
///
/// // Recomputes -8 * -8 = 64, but uses cached 64 - 1 = 63
/// let memo = memo.set_state(memo, -8)
/// memo.computed(memo) // -> 63
/// ```
pub fn chain(
  first: Deriver(a, b, d),
  second: Deriver(b, c, d),
) -> Deriver(a, c, d) {
  chain_helper(first, second, None)
}

fn chain_helper(
  first: Deriver(a, b, d),
  second: Deriver(b, c, d),
  prev_output: Option(c),
) -> Deriver(a, c, d) {
  use input, eq <- Deriver
  case first.update(input, eq), prev_output {
    Unchanged(..), Some(output) -> Unchanged(output:)
    first_deriver_output, _ -> {
      let #(first_next, first_output, first_effects) =
        unwrap_output(first_deriver_output, first)
      let #(second_next, second_output, second_effects) =
        unwrap_output(second.update(first_output, eq), second)
      // If either `first` or `second` changes, we return `Changed` even though
      // the output may be the same. This is to ensure we don't do extra work
      // in `first` on future updates.
      Changed(
        output: second_output,
        effects: list.append(second_effects, first_effects),
        next: chain_helper(first_next, second_next, Some(second_output)),
      )
    }
  }
}

/// Add an effect after another deriver. The first deriver's output will be
/// passed as the input to the effect deriver, unlike `deriver.add_effect`.
///
/// # Examples
///
/// ```gleam
/// let length_deriver: Deriver(String, Int, List(String)) =
///   deriver.new(string.length)
///   |> deriver.chain_effect(deriver.effect(fn(length) {
///     ["Length is " <> int.to_string(length)]
///   }))
///
/// let #(memo, effect) =
///   memo.from_deriver_with_effect(length_deriver, "ABC", list.flatten)
/// effect              // -> ["Length is 3"]
/// memo.computed(memo) // -> 3
///
/// let #(memo, effect) = memo.set_state_with_effect(memo, "DEF")
/// effect              // -> []
/// memo.computed(memo) // -> 3
///
/// let #(memo, effect) = memo.set_state_with_effect(memo, "ABCDEF")
/// effect              // -> ["Length is 6"]
/// memo.computed(memo) // -> 6
/// ```
pub fn chain_effect(
  deriver: Deriver(a, b, c),
  effect_deriver: Deriver(b, Nil, c),
) -> Deriver(a, b, c) {
  use input, eq <- Deriver
  case deriver.update(input, eq) {
    Unchanged(..) as result -> result
    Changed(output:, effects:, next:) -> {
      let #(effect_next, Nil, extra_effects) =
        unwrap_output(effect_deriver.update(output, eq), effect_deriver)
      Changed(
        output:,
        effects: list.append(extra_effects, effects),
        next: chain_effect(next, effect_next),
      )
    }
  }
}

/// Wraps a constructor function to be chained with `deriver.add_deriver`.
/// See the documentation of `deriver.add_deriver` for examples.
pub fn deriving(output: fn(b) -> c) -> Deriver(a, fn(b) -> c, d) {
  use _input, _eq <- Deriver
  // Output `Changed` for the first update, then `Unchanged` for all subsequent
  // updates. This is not strictly necessary, but it makes it more consistent.
  Changed(output:, effects: [], next: {
    use _input, _eq <- Deriver
    Unchanged(output:)
  })
}

/// Helper function to create a constructor function for `deriver.deriving`.
/// See the documentation of `deriver.add_deriver` for examples.
pub fn parameter(f: fn(a) -> b) -> fn(a) -> b {
  f
}

/// Along with `deriver.deriving`, this function can be used to build a
/// computed result from a chain of multiple derivers.
///
/// # Examples
///
/// ```gleam
/// let deriver: Deriver(List(Int), Computed, Nil) =
///   deriver.deriving({
///     use squared <- deriver.parameter
///     use doubled <- deriver.parameter
///     Computed(squared:, doubled:)
///   })
///   |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * x })))
///   |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * 2 })))
///
/// let memo = memo.from_deriver(deriver, [1, 2, 3])
/// memo.computed(memo) // -> Computed(squared: [1, 4, 9], doubled: [2, 4, 6])
/// ```
pub fn add_deriver(
  constructor: Deriver(a, fn(b) -> c, d),
  arg: Deriver(a, b, d),
) -> Deriver(a, c, d) {
  use constructor, arg <- map2(constructor, arg)
  constructor(arg)
}

/// Add an effect to an existing deriver. The effect deriver will take the same
/// input as the first deriver, unlike `deriver.chain_effect`.
///
/// ```gleam
/// let deriver: Deriver(List(Int), Computed, List(String)) =
///   deriver.deriving({
///     use squared <- deriver.parameter
///     use doubled <- deriver.parameter
///     Computed(squared:, doubled:)
///   })
///   |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * x })))
///   |> deriver.add_deriver(deriver.new(list.map(_, fn(x) { x * 2 })))
///   |> deriver.add_effect(
///     deriver.selecting(
///       fn(list) { result.unwrap(list.first(list), 0) },
///       deriver.effect(fn(first) {
///         ["First element: " <> int.to_string(first)]
///       }),
///     ),
///   )
///
/// let #(memo, effect) =
///   memo.from_deriver_with_effect(deriver, [1, 2, 3], list.flatten)
/// effect              // -> ["First element: 1"]
/// memo.computed(memo) // -> Computed(squared: [1, 4, 9], doubled: [2, 4, 6])
///
/// let #(memo, effect) = memo.set_state_with_effect(deriver, [1, 2, 4, 8])
/// effect              // -> []
/// memo.computed(memo) // -> Computed(squared: [1, 4, 16, 64], doubled: [2, 4, 8, 16])
///
/// let #(memo, effect) = memo.set_state_with_effect(deriver, [5])
/// effect              // -> ["First element: 5"]
/// memo.computed(memo) // -> Computed(squared: [25], doubled: [10])
/// ```
pub fn add_effect(
  deriver: Deriver(a, b, c),
  effect_deriver: Deriver(a, Nil, c),
) -> Deriver(a, b, c) {
  use result, Nil <- map2(deriver, effect_deriver)
  result
}

/// Use a custom function to check for input changes within this deriver. The
/// function should return `True` if the values are identical, and `False` if
/// they may be different.
pub fn with_custom_equality(
  deriver: Deriver(a, b, c),
  equals: fn(Dynamic, Dynamic) -> Bool,
) -> Deriver(a, b, c) {
  use input, _eq <- Deriver
  use next <- map_next(deriver.update(input, equals))
  with_custom_equality(next, equals)
}

/// Use reference equality to check for input changes within this deriver. This
/// is only applicable to the JavaScript target, so it falls back to Gleam's
/// standard deep equality on other targets.
///
/// # Implementation
///
/// On the JavaScript target, this is implemented using strict equality with
/// the `===` operator. Strings, numbers, booleans, and other primitive types
/// are compared by value, but all other objects are compared with reference
/// equality.
pub fn with_reference_equality(deriver: Deriver(a, b, c)) -> Deriver(a, b, c) {
  with_custom_equality(deriver, reference_equality)
}

/// Use shallow equality to check for input changes within this deriver. This
/// is only applicable to the JavaScript target, so it falls back to Gleam's
/// standard deep equality on other targets.
///
/// # Implementation
///
/// On the JavaScript target, this is implemented using strict equality with
/// the `===` operator for most values. However, fields of tuples are compared
/// recursively, and custom type variants with no fields are considered equal
/// if they are the same variant.
///
/// This means that it is safe to extract multiple values and put them in a
/// tuple using `deriver.selecting` without causing unnecessary recomputations.
pub fn with_shallow_equality(deriver: Deriver(a, b, c)) -> Deriver(a, b, c) {
  with_custom_equality(deriver, shallow_equality)
}

/// Use deep equality to check for input changes within this deriver. This can
/// be inefficient for large values, but it works on all targets since it is
/// implemented natively with Gleam's `==` operator.
pub fn with_deep_equality(deriver: Deriver(a, b, c)) -> Deriver(a, b, c) {
  with_custom_equality(deriver, deep_equality)
}

/// Run a deriver, producing an updated deriver, an output value, and a list of
/// effects. This is a lower-level function that provides more control than is
/// often necessary. Generally it will be better to create a `Memo` using
/// `memo.from_deriver` instead, and then allow `Memo` to handle updating the
/// deriver as necessary when the state changes.
pub fn run(
  deriver: Deriver(a, b, c),
  input: a,
) -> #(Deriver(a, b, c), b, List(c)) {
  deriver
  |> run_advanced(input)
  |> unwrap_output(deriver)
}

fn run_advanced(
  deriver: Deriver(a, b, c),
  input: a,
) -> DeriverOutput(b, c, Deriver(a, b, c)) {
  case deriver.update(input, shallow_equality) {
    Unchanged(..) as unchanged -> unchanged
    Changed(output:, effects:, next:) ->
      Changed(output:, effects: list.reverse(effects), next:)
  }
}

type DeriverOutput(output, effect, next) {
  Unchanged(output: output)
  Changed(output: output, effects: List(effect), next: next)
}

fn unwrap_output(
  deriver_output: DeriverOutput(a, b, c),
  deriver: c,
) -> #(c, a, List(b)) {
  case deriver_output {
    Unchanged(output:) -> #(deriver, output, [])
    Changed(output:, effects:, next:) -> #(next, output, effects)
  }
}

fn merge_output(
  left: DeriverOutput(a, c, d),
  right: DeriverOutput(b, c, e),
) -> DeriverOutput(#(a, b), c, #(Option(d), Option(e))) {
  let output = #(left.output, right.output)
  case left, right {
    Unchanged(..), Unchanged(..) -> Unchanged(output:)
    Unchanged(..), Changed(..) ->
      Changed(output:, effects: right.effects, next: #(None, Some(right.next)))
    Changed(..), Unchanged(..) ->
      Changed(output:, effects: left.effects, next: #(Some(left.next), None))
    Changed(..), Changed(..) ->
      Changed(
        output:,
        effects: list.append(right.effects, left.effects),
        next: #(Some(left.next), Some(right.next)),
      )
  }
}

fn map_with_default(
  deriver_output: DeriverOutput(a, c, d),
  unchanged: Option(b),
  output_mapper: fn(a) -> b,
  next_mapper: fn(b, d) -> e,
) -> DeriverOutput(b, c, e) {
  case deriver_output, unchanged {
    Unchanged(..), Some(output) -> Unchanged(output:)
    Unchanged(output:), _ -> Unchanged(output: output_mapper(output))
    Changed(output:, effects:, next:), _ -> {
      let output = output_mapper(output)
      let next = next_mapper(output, next)
      Changed(output:, effects:, next:)
    }
  }
}

fn map_next(
  deriver_output: DeriverOutput(a, b, c),
  next_mapper: fn(c) -> d,
) -> DeriverOutput(a, b, d) {
  case deriver_output {
    Unchanged(output:) -> Unchanged(output:)
    Changed(output:, effects:, next:) ->
      Changed(output:, effects:, next: next_mapper(next))
  }
}

@external(javascript, "./deriver.ffi.mjs", "refEquals")
fn reference_equality(a: a, b: a) -> Bool {
  a == b
}

@external(javascript, "./deriver.ffi.mjs", "shallowEquals")
fn shallow_equality(a: a, b: a) -> Bool {
  a == b
}

fn deep_equality(a: a, b: a) -> Bool {
  a == b
}
