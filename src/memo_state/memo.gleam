import gleam/pair
import memo_state/deriver.{type Deriver, type DeriverState}

pub opaque type Memo(state, computed, effect) {
  Memo(
    state: state,
    computed: computed,
    batch_effects: fn(List(effect)) -> effect,
    deriver_state: DeriverState(state, computed, effect),
  )
}

pub fn new(
  initial_state: a,
  batch_effects: fn(List(c)) -> c,
  compute: fn(a) -> #(b, c),
) -> #(Memo(a, b, c), c) {
  deriver.new(compute)
  |> from_deriver(initial_state, batch_effects)
}

pub fn new_simple(initial_state: a, compute: fn(a) -> b) -> Memo(a, b, Nil) {
  deriver.new_simple(compute)
  |> from_deriver_simple(initial_state)
}

pub fn from_deriver(
  deriver: Deriver(a, b, c),
  initial_state: a,
  batch_effects: fn(List(c)) -> c,
) -> #(Memo(a, b, c), c) {
  let #(deriver_state, computed, effect) =
    deriver
    |> deriver.start(batch_effects)
    |> deriver.update(initial_state)
  #(
    Memo(state: initial_state, computed:, batch_effects:, deriver_state:),
    effect,
  )
}

pub fn from_deriver_simple(
  deriver: Deriver(a, b, Nil),
  initial_state: a,
) -> Memo(a, b, Nil) {
  deriver
  |> from_deriver(initial_state, fn(_) { Nil })
  |> pair.first
}

pub fn update(memo: Memo(a, b, c), f: fn(a) -> #(a, c)) -> #(Memo(a, b, c), c) {
  let #(state, effect_a) = f(memo.state)
  let #(memo, effect_b) = set_state(memo, state)
  #(memo, memo.batch_effects([effect_a, effect_b]))
}

pub fn update_simple(memo: Memo(a, b, Nil), f: fn(a) -> a) -> Memo(a, b, Nil) {
  set_state_simple(memo, f(memo.state))
}

pub fn set_state(memo: Memo(a, b, c), new_state: a) -> #(Memo(a, b, c), c) {
  let #(deriver_state, computed, effect) =
    memo.deriver_state
    |> deriver.update(new_state)
  #(Memo(..memo, state: new_state, computed:, deriver_state:), effect)
}

pub fn set_state_simple(memo: Memo(a, b, Nil), new_state: a) -> Memo(a, b, Nil) {
  set_state(memo, new_state) |> pair.first
}

pub fn get_state(memo: Memo(a, b, c)) -> a {
  memo.state
}

pub fn get_computed(memo: Memo(a, b, c)) -> b {
  memo.computed
}
