"""
   QuikTest 

It's quick! It tests! It's **QuikTest**.

See [`quiktest`](@ref) for more.
"""
module QuikTest

import InteractiveUtils: clipboard, subtypes
import MacroTools: striplines, prewalk
import REPL.TerminalMenus: request
import Term: apply_style, highlight_syntax

using ToggleMenus

export quiktest # for now

hl(c::Union{Char,String}) = "[{bold gold1}$c{/bold gold1}]"
ico(i::Integer) = settings === icons ? "" : " ($(icons[i]))"

settings::Vector{Char} = ['k', 't', 's', 'y', 'j', 'e', 'b']

if haskey(ENV, "QUIKTEST_NO_EMOJI")
    icons = settings
else
    icons::Vector{String} = ["🧿", "✅", "📸", "🆔","🗑 ", "❌", "⚠️"]
end

head = ("$(hl('k'))eep$(ico(1)), $(hl('t'))est$(ico(2)), $(hl('s'))napshot$(ico(3)), t$(hl('y'))pe$(ico(4)), $(hl('j'))unk$(ico(5)), $(hl('e'))rror test$(ico(6)), [$(hl('b'))roken$(ico(7))",
       "Move lines $(hl('U'))p or $(hl('D'))own, $(hl('J')) to clear, $(hl('C'))lone a line, $(hl("Enter")) to accept, $(hl('q')) to quit")
header = apply_style(join(head, "\n"))

"""
    onkey(menu::ToggleMenu, i::UInt32)

The `keypress` method for the QuikTest `ToggleMenu`.  Performs all necessary
actions in response to user input.
"""
function onkey(menu::ToggleMenu, i::UInt32)
    options, selections = menu.options, menu.selections
    if Char(i) == 'J'
        selected = copy(selections)
        removals = []
        for (idx, selected) in selections |> enumerate
            if selected == 'j'
                push!(removals, idx)
                push!(removals, idx + 1)
            end
        end
        for remove in reverse(removals)
            deleteat!(options, remove)
            deleteat!(selections, remove)
        end
        menu.cursor[] = 1
        menu.pageoffset = 0
    elseif Char(i) == 'U'
        c = menu.cursor[]
        c ≤ 2 && return false  # 2 not a valid cursor position but things happen
        menu.cursor[] = c - 2
        # Move both the code line and the result line up
        options[c], options[c-2] = options[c-2], options[c]
        selections[c], selections[c-2] = selections[c-2], selections[c]
        options[c+1], options[c-1] = options[c-1], options[c+1]
        selections[c+1], selections[c-1] = selections[c-1], selections[c+1]
    elseif Char(i) == 'D'
        c = menu.cursor[]
        if c + 3 > length(options) || c + 2 ≤ length(options) && options[c+2] == ""
            return false
        end
        menu.cursor[] = c + 2
        # Move both the code line and the result line down
        options[c], options[c+2] = options[c+2], options[c]
        selections[c], selections[c+2] = selections[c+2], selections[c]
        options[c+1], options[c+3] = options[c+3], options[c+1]
        selections[c+1], selections[c+3] = selections[c+1], selections[c+3]
    elseif Char(i) == 'C'
        c = menu.cursor[]
        line = menu.options[c]
        selected = menu.selections[c]
        result = menu.options[c+1]
        insert!(menu.options, c, result)
        insert!(menu.selections, c, '\0')
        insert!(menu.options, c, line)
        insert!(menu.selections, c, selected)
    end
    return false
end

const menu = ToggleMenuMaker(header, settings, icons, 26;
                             keypress=onkey, charset=:unicode, scroll_wrap=true)

"""
    make_test_module(main::Module)

Prepare an anonymous test module `using` the module names defined in `main`.
If an expr named `QUIKTEST_PREFACE` is found in the module, this will also
be evaluated.  The module is then returned.
"""
function make_test_module(main::Module)
    # TODO we use this twice and it's expensive, we should cache it
    module_names = Symbol[]
    for name in names(main; all=true, imported=true)
        if isdefined(main, name)
            val = Base.eval(main, name)
            if val ≠ main && val isa Module
                push!(module_names, name)
            end
        end
    end
    test_mod = Base.eval(main, :(module $(gensym()) end))
    # Import existing module names on a best-effort basis
    for name in module_names
        try Base.eval(test_mod, :(using $(name)))
        catch e
        end
    end
    try
        preface = Base.eval(test_mod, :(QUIKTEST_PREFACE))
        try
            Base.eval(test_mod, preface)
        catch e  # An error in QUIKTEST_PREFACE
            @warn show(e)
        end
    catch e
        # QUIKTEST_PREFACE may not exist, this is fine
    end
    return test_mod
end

"""
    calls_quiktest(line)

Parses the line to determine if it calls quiktest.
"""
function calls_quiktest(line)
    try
        expr = Meta.parse(line)
        hasit = false
        prewalk(expr) do ex
            if ex isa Expr && ex.head == :call && expr.args[1] == :quiktest
                hasit = true
            end
        end
        return hasit
    catch e
        return false
    end
end

"""
    has_assignment(line)

Parses the line to determine if it has an assignment expression,
or defines a function.
"""
function has_assignment(line)
    expr = Meta.parse(line) # We already know this doesn't throw an error
    hasit = false
    prewalk(expr) do ex
        if ex isa Expr && (ex.head == :(=) || ex.head == :function)
            hasit = true
        end
    end
    return hasit
end

function _quiktest(numlines::Integer, stop::Integer)
    numlines = abs(numlines)
    hist = Base.active_repl.mistate.current_mode.hist
    history = hist.history
    modes = hist.modes
    lines = String[]
    count = 0
    for i = length(history)-1:-1:1
        if modes[i] == :julia && !calls_quiktest(history[i])
            push!(lines, history[i])
            count += 1
        end
        if count ≥ numlines || i ≤ stop
            break
        end
    end
    reverse!(lines)
    answers = []
    status = []
    main = Base.active_repl.mistate.active_module
    test_mod = make_test_module(main)
    io = IOBuffer()
    for line in lines
        # TODO add lookahead, parse and look for 'ans'
        # if we find it, this line is "ans = " * line
        try
            ans = quieteval(test_mod, Meta.parse(line))
            push!(answers, string(ans))
            push!(status, :answer)
        catch e
            showerror(io, e)
            push!(answers, String(take!(io)))
            push!(status, :error)
        end
    end
    options = String[]
    selections = Char[]
    line_dict = Dict{String,String}()
    for (line, answer, state) in zip(lines, answers, status)
        hl = highlight_syntax(line)
        line_dict[hl] = line
        push!(options, hl)
        if state == :answer
            # cheap heuristic
            if has_assignment(line)
                push!(selections, 'k')
            else
                push!(selections, 't')
            end
        else
            push!(selections, 'j')
        end
        push!(options, answer)
        push!(selections, '\0')
    end
    returned = request(menu(options, selections))
    tcount, the_test = prepare_test(returned, line_dict, main)
    if the_test === nothing
        println("quiktest canceled")
        return nothing
    end
    the_test |> clipboard
    Base.eval(main, :(latest_test = $(repr(the_test))))
    print("$tcount line test copied to clipboard and assigned to 'latest_test'")
end

function prepare_test(returned::Vector{Tuple{Char,String}}, line_dict::Dict{String,String}, main::Module)
    if all(x -> x[1] == '\0', returned)
        return 0, nothing
    end
    tests = String[]
    ans_mod = make_test_module(main)
    pad = "        "
    nlpad = "\n" * pad
    tcount = 0
    for (state, hi_line) in returned
        if state == '\0' || state == 'j'
            continue
        end
        tcount += 1
        line = line_dict[hi_line]
        # TODO each of the testifiers needs a careful pass to handle edge cases and
        # decide on a consistent strategy to determine the exception.  Specifically,
        # do we write the test which the result implies, or do we write a stand-in for
        # the result the user requested?
        if state == 'k'
            try
                quieteval(ans_mod, Meta.parse(line))
                str = replace(line, "\n" => nlpad)
                push!(tests, pad, str, "\n")
            catch _
                @warn "this line errors: $line"
                push!(tests, pad, "#= error in: " * line, "\n=#")
            end
        elseif state == 't'
            str = replace(testify(ans_mod, line), "\n" => nlpad)
            push!(tests, pad, str , "\n")
        elseif state == 's'
            str = replace(snaptestify(ans_mod, line), "\n" => nlpad)
            push!(tests, pad, str, "\n")
        elseif state == 'e'
            str = replace(errtestify(ans_mod, line), "\n" => nlpad)
            push!(tests, pad, str, "\n")
        elseif state == 'y'
            str = replace(typetestify(ans_mod, line), "\n" => nlpad)
            push!(tests, pad, str, "\n")
        elseif state == 'b'
            str = replace(broketestify(ans_mod, line), "\n" => nlpad)
            push!(tests, pad, str, "\n")
        end
    end
    return tcount, join(tests)
end



"""
    quiktest(), quicktest(n::Integer)

Interactively launch a menu to make tests out of recent REPL history.

Called with no arguments, this will include the entire history of the current
session. Called with an integer, it will include only that many of the most
recent lines.

When `quiktest` exits, unless canceled, it will generate _failing_ tests, on a
best-effort basis, and copy them to your clipboard.  They will also be saved
in the variable `latest_test`, as insurance against the vicissitudes of life.

**がんばって! ٩(◕‿◕)۶**
"""
function quiktest()
    !isinteractive() && error("Julia must be in interactive mode")
    hist = Base.active_repl.mistate.current_mode.hist
    _quiktest(typemax(Int64), hist.start_idx + 1)
end

function quiktest(n::Integer)
    _quiktest(n, 1)
end

# Helper functions

"""
    quieteval(mod::Module, expr)

Evaluate `expr` in `mod` while redirecting `stdout` and `stderr`
to `devnull`.  Normalizes `:symbol` answers to splice
into expressions as their represented forms.
"""
function quieteval(mod::Module, expr)
    Base.redirect_stdio(stdout=devnull, stderr=devnull) do
        ans = Base.eval(mod, expr)
        if ans isa Symbol
            return QuoteNode(ans)
        else
            return ans
        end
    end
end


"""
    compares_equal(mod::Module, ans::Any)

Check if the stringified `repr` of `ans` is `==` to the repr itself.
This confirms that the test is valid.
"""
function compares_equal(mod::Module, ans::Any)
    ans_expr = Meta.parse(stripstring(:($ans)))
    try
        return Base.eval(mod, :($ans == $ans_expr))
    catch _
        return false
    end
end

"""
    wrap_comment(test_str::String)

Wrap `test_str` in a comment, whether single or multi-line.
"""
function wrap_comment(test_str::String)
    nl = findfirst('\n', test_str)
    if nl !== nothing
        return " #= " * test_str * "\n=#"
    else
        return " # " * test_str
    end
end

stripstring(e::Any) = string(striplines(e))

# Special-case for a string, where we want a "string" back
stripstring(e::AbstractString) = repr(e)
# Same for Char
stripstring(e::AbstractChar) = repr(e)

# Placeholder symbol, we need this to splice comments into test strings
const holdsym = :🤔✅🧿😅λ
const holdstr = String(holdsym)

function testify(mod::Module, e_str::AbstractString)
    expr = (Meta.parse(e_str))
    ans = try
        quieteval(mod, expr)
    catch err
        @warn "unexpected error in: $e_str"
        if err isa LoadError
            wrong_str = wrong_error(err)
            comment =  "# test throws load error:" * wrap_comment(stripstring(:(@test_throws $holdsym @eval $expr)))
            return replace(comment, holdstr => wrong_str)
        else
            wrong_str = wrong_error(err)
            comment = "# test throws error:" * wrap_comment(stripstring(:(@test_throws $holdsym $expr)))
            return replace(comment, holdstr => wrong_str)
        end
    end
    return test_for_ans(mod, expr, ans)
end

function test_for_ans(mod::Module, expr, ans)
    # Check if the result will be a valid test
    ans_equals_ans = compares_equal(mod, ans)
    if ans_equals_ans
        if ans != false
            return stripstring(:(@test $expr == false)) * wrap_comment(stripstring(:($ans)))
        else
            return stripstring(:(@test $expr == true)) * " # false"
        end
    else  # A string will never fail this test (?) so repr it is
        ans_str = repr("text/plain", ans)
        snaptest = string(striplines(:(@test repr("text/plain", $expr) == "📸" * $ans_str)))
        return "# test did not compare `==`:" * wrap_comment(snaptest)
    end
end

function typetestify(mod::Module, e_str::AbstractString)
    expr = (Meta.parse(e_str))
    ans = try
        quieteval(mod, expr)
    catch err
        @warn "Can't test type due to error in: $e_str\n    $err"
        if err isa LoadError
            wrong_str = wrong_error(err)
            comment = "# type test throws load error:" * wrap_comment(stripstring(:(@test_throws $holdsym @eval $expr)))
            return replace(comment, holdstr => wrong_str)
        else
            wrong_str = wrong_error(err)
            comment = "# type test throws error:" * wrap_comment(stripstring(:(@test_throws $holdsym $expr)))
            return replace(comment, holdstr => wrong_str)
        end
    end
    correct_ans = :($expr isa $(typeof(ans)))
    "@test #==# " * stripstring(:(typeof($expr) == Union{})) * wrap_comment(stripstring(correct_ans))
end

function broketestify(mod::Module, e_str::AbstractString)
    expr = (Meta.parse(e_str))
    ans = try
        quieteval(mod, expr)
    catch err
        if err isa LoadError
            return string(striplines(:(@test_broken true || @eval $expr)))
        else
            return string(striplines(:(@test_broken true || $expr)))
        end
    end
    ans_equals_ans = compares_equal(mod, ans)
    if ans_equals_ans
        return string(striplines(:(@test_broken $expr == $ans)))
    else
        return string(striplines(:(@test_broken $expr != $ans)))
    end
end

function errtestify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    try
        ans = quieteval(mod, expr)
        @warn "no error in: $e_str"
        return "# No error:" * wrap_comment(test_for_ans(mod, expr, ans))
    catch err
        return _errorize(err, expr)
    end
end

function snaptestify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    ans = try
        quieteval(mod, expr)
    catch err
        @warn "can't snaptest an error, throws $(typeof(err)): $e_str"
        return "# Unexpected error in snaptest: # " * _errorize(err, expr)
    end
    if ans isa AbstractString
        ans_str = ans
    else
        ans_str = repr("text/plain", ans)
    end
    string(striplines(:(@test repr("text/plain", $expr) == "📸" * $ans_str)))
end

function wrong_error(err)
    if err isa LoadError
        wrong = "SegmentationFault"
    else
        wrong = "LoadError"
    end
    return "#= $(typeof(err)) =# $wrong"
end



function _errorize(err, expr)
    wrong_str = wrong_error(err)
    if err isa LoadError
        errtest = string(striplines(:(@test_throws $holdsym @eval $expr)))
    else
        errtest =string(striplines(:(@test_throws $holdsym $expr)))
    end
    return replace(errtest, holdstr => wrong_str)
end

end  # module QuikTest
