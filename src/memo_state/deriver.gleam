import gleam/list
import gleam/option.{type Option, None, Some}

pub opaque type Deriver(input, output, effect) {
  Deriver(
    update: fn(input) ->
      DeriverOutput(output, effect, Deriver(input, output, effect)),
  )
}

pub opaque type DeriverState(input, output, effect) {
  DeriverState(
    deriver: Deriver(input, output, effect),
    batch: fn(List(effect)) -> effect,
  )
}

pub fn new(compute: fn(a) -> #(b, c)) -> Deriver(a, b, c) {
  use input <- new_raw
  let #(output, effect) = compute(input)
  #(output, [effect])
}

pub fn new_simple(compute: fn(a) -> b) -> Deriver(a, b, c) {
  use input <- new_raw
  let output = compute(input)
  #(output, [])
}

fn new_raw(compute: fn(a) -> #(b, List(c))) -> Deriver(a, b, c) {
  use input <- Deriver
  let #(output, effects) = compute(input)
  let next = new_helper(input, output, compute)
  Changed(output:, effects:, next:)
}

fn new_helper(
  prev_input: a,
  prev_output: b,
  compute: fn(a) -> #(b, List(c)),
) -> Deriver(a, b, c) {
  use input <- Deriver
  case input == prev_input {
    True -> Unchanged(prev_output)
    False -> {
      let #(output, effects) = compute(input)
      let next = new_helper(input, output, compute)
      Changed(output:, effects:, next:)
    }
  }
}

pub fn deriving(output: b) -> Deriver(a, b, c) {
  use _input <- Deriver
  Unchanged(output)
}

pub fn selecting(
  select: fn(a) -> b,
  deriver: Deriver(b, c, d),
) -> Deriver(a, c, d) {
  use input <- Deriver
  case deriver.update(select(input)) {
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
  use input <- Deriver
  use output, next <- map_with_default(deriver.update(input), prev_output, f)
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
  use input <- Deriver
  let merged = merge_output(left.update(input), right.update(input))
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

pub fn start(
  deriver: Deriver(a, b, c),
  batch_effects: fn(List(c)) -> c,
) -> DeriverState(a, b, c) {
  DeriverState(deriver:, batch: batch_effects)
}

pub fn update(
  state: DeriverState(a, b, c),
  input: a,
) -> #(DeriverState(a, b, c), b, c) {
  let #(next, output, effect) = update_optional(state, input)
  #(option.unwrap(next, state), output, effect)
}

pub fn update_optional(
  state: DeriverState(a, b, c),
  input: a,
) -> #(Option(DeriverState(a, b, c)), b, c) {
  case state.deriver.update(input) {
    Unchanged(output:) -> #(None, output, state.batch([]))
    Changed(output:, effects:, next:) -> {
      let next_state = DeriverState(..state, deriver: next)
      let effect = effects |> list.reverse |> state.batch
      #(Some(next_state), output, effect)
    }
  }
}

type DeriverOutput(output, effect, next) {
  Unchanged(output: output)
  Changed(output: output, effects: List(effect), next: next)
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
  map_output: fn(a) -> b,
  map_next: fn(b, d) -> e,
) -> DeriverOutput(b, c, e) {
  case deriver_output, unchanged {
    Unchanged(..), Some(output) -> Unchanged(output:)
    Unchanged(output:), _ -> Unchanged(output: map_output(output))
    Changed(output:, effects:, next:), _ -> {
      let output = map_output(output)
      let next = map_next(output, next)
      Changed(output:, effects:, next:)
    }
  }
}
