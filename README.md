# QuikTest

[![Build Status](https://github.com/mnemnion/QuikTest.jl/actions/workflows/CI.yml/badge.svg?branch=trunk)](https://github.com/mnemnion/QuikTest.jl/actions/workflows/CI.yml?query=branch%3Atrunk)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

## Roadmap

- [X]  Evaluate `answer == eval(parse(answer))`, mark tests which don't pass
- [ ]  Factor the mega-functions into bite-size pieces, which can be tested,
       and used in the documentation.
- [X]  Add `[C]lone` to duplicate a line and its results.
- [ ]  Proper cursor handling for `[J]unk`.
- [ ]  Use typeof(expr) == WrongType and put the entire correct test behind the
       comment.  The test suite doesn't print anything useful for `isa` tests.
- [ ]  Write, y'know. Tests.
- [X]  Erroneous result protocol:
  - [X]  A test, snaptest, or typetest, which throws an error, becomes a comment
         with an error test
  - [X]  A test which doesn't compare equal with its result becomes a comment with
         a snaptest.
  - [X]  An error test which returns a value becomes a comment with:
    - [X]  If the value is a Type, type test
    - [X]  If the value compares equal, a test
    - [X]  If it does not compare equal, a snaptest

All of these, of course, fail.
