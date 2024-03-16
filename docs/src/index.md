# QuikTest

**QuikTest.jl** is a REPL enhancement for turning REPL sessions into tests. Quickly.

## Installation

QuikTest is most useful as a base environmental dependency, rather than a project
specific one.

Installation is as per usual:

```julia
(v1.x) pkg> install QuikTest
```

Quiktest is only useful when the REPL is running, so it should be conditionally
included within the `atreplinit()` do-block.  If you follow the practice of isolating
REPL package failures from the startup sequence, as is wise, add this:

```julia
try
    @eval using QuikTest
catch e
    @warn "error while importing QuikTest" exception=(e, catch_backtrace())
end
```

This will export one function, `quiktest`.

## Using quiktest()

If you call `quiktest()` without arguments at the REPL, it will bring up a
[ToggleMenu](https://github.com/mnemnion/ToggleMenus.jl), which will contain all the
lines from the latest REPL session. Any invocation of quiktest itself will be
filtered out, along with anything from any mode other than `julia`, so no `pkg`,
`shell`, or other such lines are included.

Below each line is the result of evaluating it.  The menu header has instructions for
how to reject lines, move them around, keep them without making them into a test, or
select the sort of test you would like the line to become.

If you exit without canceling, by pressing Enter, QuikTest will generate _failing_
tests for each line so chosen.  These are copied to the clipboard, and also assigned
to the variable `latest_test`, just in case something happens to the clipboard
between running QuikTest and pasting your new tests into `runtests.jl`, or wherever
in your test suite you would like.

`quiktest` can be called with a number, in which case, the last `n` lines which
QuikTest considers valid will be displayed in the menu.  So `quiktest(3)` will give
you three lines, which won't include the invocation of `quiktest`, or lines from
modes which aren't Julia.

That's it! It's quick, it's tests, it's **QuikTest.jl**.

```@setup qt1
import REPL.TerminalMenus: printmenu
import QuikTest: menu

# Make a fake quiktest

function quiktest()
   io = IOBuffer()
   options = [""""this string" != "that string" """,
              "true",
              "[:moe, :curly, :larry]",
              "[:moe, :curly, :larry]",
              "2 + 3",
              "5"]
   printmenu(io, menu(options, ['t', '\0', 't', '\0','t', '\0']), 1)
   str = String(take!(io))
   str = replace(str, r"\r\e\[\d+A\e\[2K" => "")
   print(str)
end
```

```@repl qt1
"this string" != "that string"

[:moe, :curly, :larry]

2 + 3

quiktest()
```

### Did You Say "Failing Tests"?

Yes. QuikTest will never generate a test which will pass, if this happens, please file a bug.

Instead, it will generate a failing test, structured so that it's easy (quick!) to
turn this into a passing test, once the tests are run and the new tests are confirmed
to fail.  These are designed such that the standard test framework will print the
correct answer when it fails.

#### Why Though?

The author of QuikTest subscribes to the school of thought which holds that, until a
test has failed, it isn't a test.  A test may pass, or it may *appear* to pass, for
instance, by not being a test at all.  Or worse, a coincidence of errors may mean
that it passes, but for the wrong reasons.  Only once a test has failed is it truly a
test.  This is the Way.

## Using the QuikTest Menu

When `quiktest` is invoked, it launches a
[ToggleMenu](https://github.com/mnemnion/ToggleMenus.jl), a TerminalMenu designed
especially for QuikTest.  At start, any line which throws an error is marked as junk,
with a 🗑 emoji, a line with an assignment in it is marked 🧿 for keeping, and any
other line is marked as a test, with ✅.  From there, you're free to change these
defaults to any choice you would like.

Basic navigation works like any other TerminalMenu: up and down arrows to move
around, `PgUp` and `PgDown` to page, `Home` and `End` for the top and bottom, `q` to
quit, `Enter` to exit the menu and create tests.  The tab key will toggle a line
between states, left and right arrows will cycle the state back and forward, or you
can assign a state directly by pressing the highlighted letter for that state.

---

- States:
  - 🧿 **'k'**:  Keeps the line, but doesn't make it into a test. Use this for lines
          which set up state for subsequent tests.  This is the default for assignments
          and function definitions.
  - ✅ **'t'**:  An ordinary test.  The test will compare the line to its results, using
          `==`.  This is of necessity somewhat sensitive to the result of calling
          two-argument `show` on the result, as well as, of course, the definition of
          `==` for the type.
  - 📸 **'s'**:  A snapshot test.  This compares the _repr_ of the test line to a
          string of its current return value.  This sort of test can be brittle, but
          is correct for testing the repr itself, and can be expedient under other
          circumstances. This uses three-argument show, which is to say, the result
          compared against is exactly what you will see at the REPL.
  - 🆔 **'y'**:  A type test.  The result of the line is compared to the type of the
          result using `isa`.
  - 🗑 **'j'**:  Junk the line, that is, do not include it in the test.  This is the
          default for lines which throw errors.  If you want to test for the error,
          use:
  - ❌ **'e'**:  Error test.  A `@test_throws` test is generated, which tests against the
          `Exception` type thrown by the line.
  - ⚠️ **'b'**:  A broken test.  Creates a `@test_broken`. Like any QuikTest test, this
          _will not pass_, because the test will pass, meaning it fails.  You will
          want to modify such tests so that they compare against the expected value
          when the test is no longer broken.

---

- Additional Commands:
  - **U** and **D**:  These move tests up and down in the list.  This can be for
        presentation purposes, or because a setup line wants to be before a
        test line, but they were entered into the REPL in the wrong order.  The tests
        will be generated by evaluating the lines in the final order when the menu is
        exited.
  - **J**:  Removes all junk lines from the menu.  This may be called at any time to
          clear up unwanted lines, so you can focus on the remaining lines of interest.
          This will do the right thing even if you junk all the lines in the menu,
          although there is never a reason to do this.

---

## How It Works

QuikTest searches the REPL history to retrieve the lines of interest, and evaluates
them in an "anonymous" module. Julia doesn't actually have anonymous modules,
so QuikTest contains an inner, private submodule, which is used entirely to generate
modules with a gensymed name.

As it happens, the REPL keeps track of the active module, so we don't have to guess.
Quiktest searches through the active module for any other named modules, and adds
them with `using` to the anonymous module.  The REPL lines are then evaluated, the
results of this stringified, and the menu built.  Lines which throw errors are marked
junk, assignments are marked keep, and the rest are marked test.

No further evaluation is performed while the menu is active, so you'll want to
classify lines on the basis of what you expect to happen.  Which might differ from
what happened the first time: rearranging lines can turn an error into a valid line,
and vice-versa. In the first case one might select ✅ for a line whose result shows an
error, and in the second case one might select ❌ for a line which doesn't show an
error currently.  If these assumptions are incorrect, QuikTest will exhibit
reasonable behavior.

If you press `q`, QuikTest will exit, and inform you that you canceled. If you press
`Enter`, QuikTest will do its best to construct failing tests of the indicated types.
These will always be constructed such that the user may turn them into a passing test
by deleting some part of the test as provided; what must be removed will be obvious.
This is accomplished by creating another module, into which the remaining lines are
evaluated, in the order they appear when the menu is exited.

If, for any reason, QuikTest is unable to generate a test which _will_ pass once
modified, it will issue a warning, and generate a comment.   This can happen if an
ordinary test is requested for a line which throws an error, or if an error test is
requested for a line which doesn't throw one, or if, after stringulation, the value
of a result is not `==` to the result itself.  The comment will include a test
(failing of course) which _would_ be valid for the line: for instance, if an ordinary
test throws an error, the commented-out test will use `@test_throws`, or if the answer
(after being stringified) doesn't `==` the expression, a snaptest will be generated.

These comment lines may simply be removed, or the test portion tweaked into something
correct.  Or leave them as a placeholder while you fix whatever caused it to be
invalid, your call.

Finally, these are copied to the clipboard, as well as the `latest_test` variable. If
you lose the test string due to some other clipboard action, `latest_test |>
clipboard` will put it right back.

The workflow from there is to paste the tests into a testset, run the tests to
confirm that they fail, and do a bit of targeted deletion to make them green.  Bob is
now your proverbial uncle.

## Tips

**QuikTest** really is designed for quick tests.  The smooth workflow is, as soon as
you see behavior at the REPL which you want to preserve, call `quiktest`.  You may
find setting up long and complex tests is better done directly in the test suite.
Used as intended, doing the usual sort of REPL-driven development, and punctuating it
with frequent, small tests, as soon as the program exhibits desirable behavior, one
gains a strong test suite a little bit at a time.  Reducing the need to switch to
"writing tests mode" is the very motive of **QuikTest.jl**.

If you do find yourself wanting to set up a longer sequence of tests, it's probably a
good idea to reboot the REPL, rather than laboriously count back the lines you intend
to test, or call `quiktest()` and manually junk a very large number of lines.
Although it's easy enough to guess-and-check: if you call, say `quiktest(7)`, and a
couple lines are missing, just press `[q]` and call `quiktest(9)`. Lines containing a
call to `quiktest` are never counted, so there's no need to account for them.

`QuikTest` isn't a separate mode, in the REPL sense, but setting up good tests does
call for a particular technique. `QuikTest` is unaware of `ans` in the normal Julian
REPL mode, or `Out[n]` in the numbered prompt mode. If you use these in a test, you
won't get the results you want.

Bringing us to the next tip: QuikTest makes tests which don't meet the requirement
for that type of test into a comment, and the comment contains the type of test which
would meet the requirement: for example, if a line marked ✅ for test throws an error,
the commented-out test will be in the form for a line marked ❌ for error test.  Sometimes
you just want to smuggle a test into the suite and edit it into shape.  Use a broken test
for this (⚠️), it will make the most minimal changes to the part of the test you want.

Especially if you're accustomed to writing your tests at the REPL already, you may be
tempted to use `==` to compare a result with its expected value.  `QuikTest` makes no
attempt to detect or correct for this, what you'll end up with is not the test you want.

```jldoctest
julia> fruits = Dict(:a => "apple", :b => "berry")
Dict{Symbol, String} with 2 entries:
  :a => "apple"
  :b => "berry"

julia> fruits[:a] == "apple"  # No
true

julia> fruits[:a]  # Yes
"apple"
```

Let **QuikTest** do the work for you!

Compare the results:

```julia
fruits = Dict(:a => "apple", :b => "berry")
@test (fruits[:a] == "apple") == false # true
@test fruits[:a] == false # "apple"
```

Next tip: when you add a line intended for one of the nonstandard tests, a type test,
snaptest, or broken test, drop a comment to remind yourself what it's for.  They're
easy to lose track of when you start editing the session into tests.

The various evaluations involved in producing the final test will swallow any
comments, so conversely, don't try to add comments you want in the test suite
to the REPL session, it won't work.  The natural time to add such comments is after
the tests are pasted in, you've run the suite to confirm they fail, and are editing
them to pass.

Favor writing tests a few at a time. The pagesize for the `QuikTest` menu includes 13
lines with their results, after which paging is necessary, this is a reasonable
heuristic for a maximum size for a `QuikTest` session.  If you want more tests out of
a given setup, assuming that setup is at the beginning of your test session, it's
easy to copy-paste those lines in the terminal, then remove the duplicates when
pasted into the test.

## Configuring QuikTest

Optimistically including any modules in the namespace with `using` is often
sufficient to replicate the state of the lines evaluated (that is, only an error in
the REPL is an error in QuikTest), but not always.  The obvious way for this to fail
is when `import` statements bring in names which are not exported, or are from modules
whose names aren't imported into the REPL module, or both.  If `import` statements
are among the lines executed in the REPL, they will be evaluated, but if they aren't
included due to `quiktest(n)` or if executed from lines which aren't entered at the
REPL, these names will not be available.

To solve this class of issue, QuikTest attempts to evalute an Expr called
`QUIKTEST_PREFACE`, which comes between the autogenerated `using` statements and the
evaluation of REPL history.  This offers a convenient place to define necessary
additional import statements, and possibly perform other sorts of setup, though the
latter is somewhat brittle.  If this name is not defined, or it isn't an Expr, this
will have no effect; if evaluating `QUIKTEST_PREFACE` throws an error, a warning will
occur.

A suggestion for integrating this: the last lines of my `startup.jl` look for a file
in the current directory called `start.jl` (which my standard PkgTemplate adds to
`.gitignore`) and executes it if found, as the last action before going live.  There
I put `using` statements relevant to developing that specific package, any `import`
statements which are also useful, and sometimes use it as a scratchpad for helper
functions of the ephemeral variety, those which come and go over the course of
development.  Or lengthy example data which would be onerous to enter or paste at the
REPL.  That sort of thing.

To integrate these with QuikTest, I do something like this:

```julia
const QUIKTEST_PREFACE = quote
    using WidgetProviders
    using AbstractGizmoFactory
    import AwesomeWidgets: TurboEncabulator
end

eval(QUIKTEST_PREFACE)
```

It's harmless to include the `using` statements in the Expr, they get evaluated twice
due to the auto-include but nothing untoward happens as a result.  This keeps a
single source of truth, and practically guarantees that necessary names will be
present in the evaluation modules.

### What If I Hate Emoji?

Or just don't want them as cutesy icons, or your terminal doesn't support them well,
or what have you.

Before QuikTest is loaded, do something like this:

```julia
ENV["QUIKTEST_NO_EMOJI"] = "I hate emoji!!! 🤬🤬🤬"
```

Use whatever you'd like as the value, QuikTest just checks for the key.  This will
completely remove QuikTest-provided emoji from the toggle menu.  Note that this is
checked once, during loading, and as such is not configurable at runtime.

QuikTest does not currently offer a way to remove color from its menus.  An upcoming
refactor to use StyledStrings after the Julia 1.11 release will provide an
opportunity to do so, so a future release will respect the value of the `--color` flag
used when starting `julia`.

## Caveats

For the most part, if a test works in QuikTest, it will work in the test suite.  The
main exceptions to this arise from certain actions being only legal in the top scope,
which a testset is not.  It would be possible to simulate this, for example, by
wrapping each line in a `let` block, but doing so would only interfere with the goal
of QuikTest, which is to make tests, quickly, from REPL input.  For example, if the
user were to use a `const` expression in the REPL, this would fail when the tests are
run, but the solution is to simply remove the offending keyword.

There are also the [minor scope
differences](https://docs.julialang.org/en/v1.10/manual/variables-and-scoping/#on-soft-scope)
between interactive and non-interactive use, and these can also lead to erroneous
tests under some rare circumstances. But again, these are easy to fix: running the
tests will print a clear warning, and either `local` or `global`, depending on
intention, can be applied.

Of course, QuikTest uses the REPL module context, and `QUIKTEST_PREFACE`, to
evaluate, not the module of the test suite.  The user is responsible for making sure
that symbols resolve correctly to their intended values, by adding the necessary
`using` and `import` statements to the test file itself.  If it would be useful to
you to keep that in sync automatically, you might define a small `.jl` file
containing `QUIKTEST_PREFACE`, and eval that in the test suite, as well as when the
REPL starts up.

Last, we have less of a caveat, and more of a statement about the scope and mission
of QuikTests.  The project intentionally embraces a simple workflow, and doesn't
cover some cases which a more maximalist project might.  For example, I considered
adding a picker menu for complex return values, and combining that with a signal for
when comparing a line to its result doesn't constitute a valid test.  But a picker
menu is a very complex project, possibly larger than QuikTest itself.  The intended
workflow is to work through the menu, paste in the tests, delete the ones which
aren't satisfactory, head back to the REPL to use its fully-featured editing tools to
narrow down a return value, then run quiktest again.  QuikTest doesn't generate
testsets directly, and offers no affordances for several things which the `Test`
package is able to do.

You might still have to write slow tests, in other words. But for quick tests,
QuikTest has got your back.

## Bugs and (Mis) Features

If you find a case where QuikTest doesn't do the right thing, especially if it
generates a test which can't be trivially modified (subject to the above caveats)
into a passing test, please file an issue.  If QuikTest ever generates a test which
passes without modification, this is _also a bug_, please file an issue, I am quite
serious here.

QuikTest relies heavily on undocumented Julia internals, including some truly obscure
ones, and might easily break from a minor or even patch upgrade. If this happens to
you, please file an issue right away so I can fix it.  That fix will keep backward
compatibility if it's easy to do so, if it's not, it won't.

If you would like QuikTest to do some additional test-related thing, and you have a
good idea for how it should work, you may certainly file an issue on this as well.  I
may or may not agree that it's in keeping with the philosophy of the package, but it
can't hurt to ask politely.

If you would like QuikTest to write passing tests, rather than failing tests which
may be easily modified to pass, you're on your own, because QuikTest will never do
that.  Please do not file an issue just so I can close it with `#wontfix`.  Thank you.