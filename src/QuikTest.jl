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
       "Move lines $(hl('U'))p or $(hl('D'))own, {$(hl('J')) to clear, $(hl("Enter")) to accept, $(hl('q')) to quit")
header = apply_style(join(head, "\n"))

# A QuikTest local module to hold test modules. A module module, one might say.
baremodule ModMod end

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
    end
    return false
end

const menu = ToggleMenuMaker(header, settings, icons, 20, keypress=onkey, scroll_wrap=true)

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
        if isdefined(Main, name)
            val = Base.eval(Main, name)
            if val ≠ main && val isa Module
                push!(module_names, name)
            end
        end
    end
    test_mod = Base.eval(ModMod, :(module $(gensym()) end))
    # Import existing module names on a best-effort basis
    for name in module_names
        try Base.eval(test_mod, :(using $(name)))
        catch e
        end
    end
    try
        preface = Base.eval(main, :(QUIKTEST_PREFACE))
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
session.  Called with an integer, it will include only that many of the most
recent lines.
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
to `devnull`.
"""
function quieteval(mod::Module, expr)
    Base.redirect_stdio(stdout=devnull, stderr=devnull) do
        return Base.eval(mod, expr)
    end
end

stripstring(e) = string(striplines(e))

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
            comment =  "#= unexpected error: # " * stripstring(:(@test_throws $holdsym @eval $expr)) * "\n# =#"
            return replace(comment, holdstr => wrong_str)
        else
            wrong_str = wrong_error(err)
            comment = "#= unexpected error: # " * stripstring(:(@test_throws $(wrong_error(err)) $expr)) * "\n# =#"
            return replace(comment, holdstr => wrong_str)
        end
    end
    if ans isa Symbol
        ans = QuoteNode(ans)
    end
    # TODO turn ans into a string, parse it, paste this into an Expr :($ans = $str_ans),
    # and evaluate that to determine if the test will pass once the fail-slug is removed.
    if ans != false
        return stripstring(:(@test $expr == false)) * " # " * stripstring(:($ans))
    else
        return stripstring(:(@test $expr == true)) * " # false"
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
            comment = "#= unexpected error: # " * string(striplines(:(@test_throws $holdsym @eval $expr))) * "\n# =#"
            return replace(comment, holdstr => wrong_str)
        else
            wrong_str = wrong_error(err)
            comment = "#= unexpected error: # " * string(striplines(:(@test_throws $holdsym $expr))) * "\n# =#"
            return replace(comment, holdstr => wrong_str)
        end
    end
    string(striplines(:(@test $expr isa Union{}))) * " # $(typeof(ans))"
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
    if ans isa Symbol
        ans = QuoteNode(ans)
    end
    string(striplines(:(@test_broken $expr == $ans)))
end

function errtestify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    try
        ans = quieteval(mod, expr)
        @warn "no error in: $e_str"
        wrong = ans == false ? true : false
        return "#= No error: # " * stringstrip(:(@test $expr == $wrong)) * " # " * stringstrip(:($ans)) * "\n# =#"
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
        return "#= Unexpected error: " * _errorize(ans, err) * "\n=#"
    end
    if ans isa AbstractString
        ans_str = ans
    else
        ans_str = repr(ans)
    end
    string(striplines(:(@test repr($expr) == "📸" * $ans_str)))
end

function wrong_error(e::Exception)
    if e isa LoadError
        wrong = "SegmentationFault"
    else
        wrong = "LoadError"
    end
    return "#= $(typeof(e)) =# $wrong"
end



function _errorize(err::Exception, expr)
    wrong_str = wrong_error(err)
    if err isa LoadError
        errtest = string(striplines(:(@test_throws $holdsym @eval $expr)))
    else
        errtest =string(striplines(:(@test_throws $holdsym $expr)))
    end
    return replace(errtest, holdstr => wrong_str)
end

end  # module QuikTest
