import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}

pub opaque type Deriver(input, output, effect) {
  Deriver(
    update: fn(input, fn(Dynamic, Dynamic) -> Bool) ->
      DeriverOutput(output, effect, Deriver(input, output, effect)),
  )
}

pub fn new(compute: fn(a) -> b) -> Deriver(a, b, c) {
  use input <- new_raw
  let output = compute(input)
  #(output, [])
}

pub fn new_with_effect(compute: fn(a) -> #(b, c)) -> Deriver(a, b, c) {
  use input <- new_raw
  let #(output, effect) = compute(input)
  #(output, [effect])
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

pub fn deriving(output: b) -> Deriver(a, b, c) {
  use _input, _eq <- Deriver
  // Output `Changed` for the first update, then `Unchanged` for all subsequent
  // updates. This is not strictly necessary, but it makes it more consistent.
  Changed(output:, effects: [], next: {
    use _input, _eq <- Deriver
    Unchanged(output:)
  })
}

pub fn selecting(
  select: fn(a) -> b,
  deriver: Deriver(b, c, d),
) -> Deriver(a, c, d) {
  use input, eq <- Deriver
  case deriver.update(select(input), eq) {
    Unchanged(output:) -> Unchanged(output:)
    Changed(output:, effects:, next:) ->
      Changed(output:, effects:, next: selecting(select, next))
  }
}

pub fn map(deriver: Deriver(a, b, d), f: fn(b) -> c) -> Deriver(a, c, d) {
  map_helper(deriver, f, None)
}

fn map_helper(
  deriver: Deriver(a, b, d),
  f: fn(b) -> c,
  prev_output: Option(c),
) -> Deriver(a, c, d) {
  use input, eq <- Deriver
  use output, next <- map_with_default(
    deriver.update(input, eq),
    prev_output,
    f,
  )
  map_helper(next, f, Some(output))
}

pub fn map2(
  left: Deriver(a, b, e),
  right: Deriver(a, c, e),
  f: fn(b, c) -> d,
) -> Deriver(a, d, e) {
  let mapper = fn(pair: #(b, c)) -> d { f(pair.0, pair.1) }
  map2_helper(left, right, mapper, None)
}

fn map2_helper(
  left: Deriver(a, b, e),
  right: Deriver(a, c, e),
  mapper: fn(#(b, c)) -> d,
  prev_output: Option(d),
) -> Deriver(a, d, e) {
  use input, eq <- Deriver
  let merged = merge_output(left.update(input, eq), right.update(input, eq))
  use output, #(next_left, next_right) <- map_with_default(
    merged,
    prev_output,
    mapper,
  )
  map2_helper(
    option.unwrap(next_left, left),
    option.unwrap(next_right, right),
    mapper,
    Some(output),
  )
}

pub fn then(left: Deriver(a, b, d), right: Deriver(b, c, d)) -> Deriver(a, c, d) {
  then_helper(left, right, None)
}

fn then_helper(
  left: Deriver(a, b, d),
  right: Deriver(b, c, d),
  prev_output: Option(c),
) -> Deriver(a, c, d) {
  use input, eq <- Deriver
  case left.update(input, eq), prev_output {
    Unchanged(..), Some(output) -> Unchanged(output:)
    left_deriver_output, _ -> {
      let #(left_output, left_effects, left_next) =
        to_changed(left_deriver_output, left)
      let #(right_output, right_effects, right_next) =
        to_changed(right.update(left_output, eq), right)
      // If either `left` or `right` changes, we return `Changed` even though
      // the output may be the same. This is to ensure we don't do extra work
      // in `left` on future updates.
      Changed(
        output: right_output,
        effects: list.append(right_effects, left_effects),
        next: then_helper(left_next, right_next, Some(right_output)),
      )
    }
  }
}

pub fn with_equality(
  deriver: Deriver(a, b, c),
  equals: fn(Dynamic, Dynamic) -> Bool,
) -> Deriver(a, b, c) {
  use input, _eq <- Deriver
  use next <- map_next(deriver.update(input, equals))
  with_equality(next, equals)
}

pub fn add_deriver(
  f: Deriver(a, fn(b) -> c, d),
  arg: Deriver(a, b, d),
) -> Deriver(a, c, d) {
  use f, arg <- map2(f, arg)
  f(arg)
}

pub fn parameter(f: fn(a) -> b) -> fn(a) -> b {
  f
}

pub fn update(
  deriver: Deriver(a, b, c),
  input: a,
) -> #(Deriver(a, b, c), b, List(c)) {
  let #(next, output, effect) = update_optional(deriver, input)
  #(option.unwrap(next, deriver), output, effect)
}

pub fn update_optional(
  deriver: Deriver(a, b, c),
  input: a,
) -> #(Option(Deriver(a, b, c)), b, List(c)) {
  case deriver.update(input, shallow_equality) {
    Unchanged(output:) -> #(None, output, [])
    Changed(output:, effects:, next:) -> {
      #(Some(next), output, list.reverse(effects))
    }
  }
}

type DeriverOutput(output, effect, next) {
  Unchanged(output: output)
  Changed(output: output, effects: List(effect), next: next)
}

fn to_changed(
  deriver_output: DeriverOutput(a, b, c),
  deriver: c,
) -> #(a, List(b), c) {
  case deriver_output {
    Unchanged(output:) -> #(output, [], deriver)
    Changed(output:, effects:, next:) -> #(output, effects, next)
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
  next_mapper: fn(c) -> c,
) -> DeriverOutput(a, b, c) {
  case deriver_output {
    Unchanged(output:) -> Unchanged(output:)
    Changed(output:, effects:, next:) ->
      Changed(output:, effects:, next: next_mapper(next))
  }
}

@external(javascript, "./deriver.ffi.mjs", "refEquals")
pub fn reference_equality(a: a, b: a) -> Bool {
  a == b
}

@external(javascript, "./deriver.ffi.mjs", "shallowEquals")
pub fn shallow_equality(a: a, b: a) -> Bool {
  a == b
}

pub fn deep_equality(a: a, b: a) -> Bool {
  a == b
}
