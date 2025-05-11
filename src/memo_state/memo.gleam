import gleam/pair
import memo_state/deriver.{type Deriver}

pub opaque type Memo(state, computed, effect) {
  Memo(
    state: state,
    computed: computed,
    batch_effects: fn(List(effect)) -> effect,
    deriver: Deriver(state, computed, effect),
  )
}

pub fn new(initial_state: a, compute: fn(a) -> b) -> Memo(a, b, Nil) {
  deriver.new(compute)
  |> from_deriver(initial_state)
}

pub fn new_with_effect(
  initial_state: a,
  batch_effects: fn(List(c)) -> c,
  compute: fn(a) -> #(b, c),
) -> #(Memo(a, b, c), c) {
  deriver.new_with_effect(compute)
  |> from_deriver_with_effect(initial_state, batch_effects)
}

pub fn from_deriver(
  deriver: Deriver(a, b, Nil),
  initial_state: a,
) -> Memo(a, b, Nil) {
  deriver
  |> from_deriver_with_effect(initial_state, fn(_) { Nil })
  |> pair.first
}

pub fn from_deriver_with_effect(
  deriver: Deriver(a, b, c),
  initial_state: a,
  batch_effects: fn(List(c)) -> c,
) -> #(Memo(a, b, c), c) {
  let #(deriver, computed, effects) =
    deriver
    |> deriver.update(initial_state)
  #(
    Memo(state: initial_state, computed:, batch_effects:, deriver:),
    batch_effects(effects),
  )
}

pub fn update(memo: Memo(a, b, Nil), f: fn(a) -> a) -> Memo(a, b, Nil) {
  set_state(memo, f(memo.state))
}

pub fn update_with_effect(
  memo: Memo(a, b, c),
  f: fn(a) -> #(a, c),
) -> #(Memo(a, b, c), c) {
  let #(new_state, update_effect) = f(memo.state)
  let #(deriver, computed, effects) = deriver.update(memo.deriver, new_state)
  let effect = memo.batch_effects([update_effect, ..effects])
  #(Memo(..memo, state: new_state, computed:, deriver:), effect)
}

pub fn set_state(memo: Memo(a, b, Nil), new_state: a) -> Memo(a, b, Nil) {
  let #(deriver, computed, _effects) = deriver.update(memo.deriver, new_state)
  Memo(..memo, state: new_state, computed:, deriver:)
}

pub fn set_state_with_effect(
  memo: Memo(a, b, c),
  new_state: a,
) -> #(Memo(a, b, c), c) {
  let #(deriver, computed, effects) = deriver.update(memo.deriver, new_state)
  #(
    Memo(..memo, state: new_state, computed:, deriver:),
    memo.batch_effects(effects),
  )
}

pub fn state(memo: Memo(a, b, c)) -> a {
  memo.state
}

pub fn computed(memo: Memo(a, b, c)) -> b {
  memo.computed
}
