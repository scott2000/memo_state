-module(memo_state_ffi).

-export([call_eq/3]).

call_eq(Eq, A, B) ->
    Eq(A, B).
