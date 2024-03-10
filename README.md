# QuikTest

[![Build Status](https://github.com/mnemnion/QuikTest.jl/actions/workflows/CI.yml/badge.svg?branch=trunk)](https://github.com/mnemnion/QuikTest.jl/actions/workflows/CI.yml?query=branch%3Atrunk)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)


## Roadmap

- [ ]  Evaluate `answer == eval(parse(answer))`, mark tests which don't pass
- [ ]  It turns out you can pass a cursor Ref to `request`, so that can be attached to
       the .aux field and used to move the cursor around for up/down, and rescue it from
       limbo when lines are junked.