import cat/monoid.{type Monoid}
import gleam/option.{type Option, None, Some}

pub opaque type Deriver(input, output, effect) {
  Deriver(
    with_monoid: fn(Monoid(effect)) -> DeriverState(input, output, effect),
  )
}

pub opaque type DeriverState(input, output, effect) {
  DeriverState(
    monoid: Monoid(effect),
    update: fn(input) ->
      DeriverOutput(output, effect, DeriverState(input, output, effect)),
  )
}

pub fn new(compute: fn(a) -> #(b, c)) -> Deriver(a, b, c) {
  use monoid <- Deriver
  use input <- DeriverState(monoid)
  let #(output, effect) = compute(input)
  let next = new_helper(monoid, input, output, compute)
  Changed(output:, effect:, next:)
}

fn new_helper(
  monoid: Monoid(c),
  prev_input: a,
  prev_output: b,
  compute: fn(a) -> #(b, c),
) -> DeriverState(a, b, c) {
  use input <- DeriverState(monoid)
  case input == prev_input {
    True -> Unchanged(prev_output)
    False -> {
      let #(output, effect) = compute(input)
      let next = new_helper(monoid, input, output, compute)
      Changed(output:, effect:, next:)
    }
  }
}

pub fn simple(compute: fn(a) -> b) -> Deriver(a, b, c) {
  use monoid <- Deriver
  let empty = monoid.mempty
  let deriver = new(fn(input) { #(compute(input), empty) })
  deriver.with_monoid(monoid)
}

pub fn deriving(output: b) -> Deriver(a, b, c) {
  use monoid <- Deriver
  use _input <- DeriverState(monoid)
  Unchanged(output)
}

pub fn selecting(
  select: fn(a) -> b,
  deriver: Deriver(b, c, d),
) -> Deriver(a, c, d) {
  use monoid <- Deriver
  let state = deriver.with_monoid(monoid)
  selecting_helper(select, state)
}

fn selecting_helper(
  select: fn(a) -> b,
  state: DeriverState(b, c, d),
) -> DeriverState(a, c, d) {
  use input <- DeriverState(state.monoid)
  case state.update(select(input)) {
    Unchanged(output:) -> Unchanged(output:)
    Changed(output:, effect:, next:) ->
      Changed(output:, effect:, next: selecting_helper(select, next))
  }
}

pub fn map(deriver: Deriver(a, b, d), f: fn(b) -> c) -> Deriver(a, c, d) {
  use monoid <- Deriver
  let state = deriver.with_monoid(monoid)
  map_helper(state, f, None)
}

fn map_helper(
  state: DeriverState(a, b, d),
  f: fn(b) -> c,
  prev_output: Option(c),
) -> DeriverState(a, c, d) {
  use input <- DeriverState(state.monoid)
  use output, next <- map_with_default(state.update(input), prev_output, f)
  map_helper(next, f, Some(output))
}

pub fn map2(
  left: Deriver(a, b, e),
  right: Deriver(a, c, e),
  f: fn(b, c) -> d,
) -> Deriver(a, d, e) {
  use monoid <- Deriver
  let state_left = left.with_monoid(monoid)
  let state_right = right.with_monoid(monoid)
  let mapper = fn(pair: #(b, c)) -> d { f(pair.0, pair.1) }
  map2_helper(state_left, state_right, mapper, None)
}

fn map2_helper(
  left: DeriverState(a, b, e),
  right: DeriverState(a, c, e),
  mapper: fn(#(b, c)) -> d,
  prev_output: Option(d),
) -> DeriverState(a, d, e) {
  let monoid = left.monoid
  use input <- DeriverState(monoid)
  let merged = merge_output(left.update(input), right.update(input), monoid)
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

pub fn finish(
  deriver: Deriver(a, b, c),
  monoid: Monoid(c),
) -> DeriverState(a, b, c) {
  deriver.with_monoid(monoid)
}

pub fn update(
  state: DeriverState(a, b, c),
  input: a,
) -> #(DeriverState(a, b, c), b, c) {
  case state.update(input) {
    Unchanged(output:) -> #(state, output, state.monoid.mempty)
    Changed(output:, effect:, next:) -> #(next, output, effect)
  }
}

type DeriverOutput(output, effect, next) {
  Unchanged(output: output)
  Changed(output: output, effect: effect, next: next)
}

fn merge_output(
  left: DeriverOutput(a, c, d),
  right: DeriverOutput(b, c, e),
  monoid: Monoid(c),
) -> DeriverOutput(#(a, b), c, #(Option(d), Option(e))) {
  let output = #(left.output, right.output)
  case left, right {
    Unchanged(..), Unchanged(..) -> Unchanged(output:)
    Unchanged(..), Changed(..) ->
      Changed(output:, effect: right.effect, next: #(None, Some(right.next)))
    Changed(..), Unchanged(..) ->
      Changed(output:, effect: left.effect, next: #(Some(left.next), None))
    Changed(..), Changed(..) ->
      Changed(
        output:,
        effect: monoid.mappend(left.effect, right.effect),
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
    Changed(output:, effect:, next:), _ -> {
      let output = map_output(output)
      let next = map_next(output, next)
      Changed(output:, effect:, next:)
    }
  }
}
