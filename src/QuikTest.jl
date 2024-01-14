module QuikTest

import InteractiveUtils: clipboard, subtypes
import MacroTools: striplines
import REPL.TerminalMenus: request
import Term: apply_style, highlight_syntax

using ToggleMenus

export menu, quiktest # for now

head = ("[{bold gold1}k{/bold gold1}]eep (🧿), [{bold gold1}t{/bold gold1}]est (✅), [{bold gold1}s{/bold gold1}]napshot (📸), [{bold gold1}j{/bold gold1}]unk (🗑 ), [{bold gold1}e{/bold gold1}]rror test (❗️), [{bold gold1}b{/bold gold1}]roken (⚠️)",
       "[{bold gold1}U{/bold gold1}]p, [{bold gold1}D{/bold gold1}]own, {bold gold1}J{/bold gold1} to clear")
const header = apply_style(join(head, "\n"))
const settings::Vector{Char} = ['k', 't', 's', 'j', 'e', 'b']
const icons::Vector{String} = ["🧿", "✅", "📸", "🗑 ", "❗️", "⚠️"]

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
        for _ = 1:length(removals)
            push!(options, "")
            push!(selections, '\0')
        end
    # TODO get the indexing right on these
    elseif Char(i) == 'U'
        c = menu.cursor
        c == 1 && return false
        options[c], options[c-2] = options[c-2], options[c]
        selections[c], selections[c-2] = selections[c-2], selections[c]
        options[c+1], options[c-1] = options[c-1], options[c+1]
        selections[c+1], selections[c-1] = selections[c-1], selections[c+1]
    elseif Char(i) == 'D'
        c = menu.cursor
        if c + 3 > length(options) || c + 2 ≤ length(options) && options[c+2] == ""
            return false
        end
        options[c], options[c+2] = options[c+2], options[c]
        selections[c], selections[c+2] = selections[c+2], selections[c]
        options[c+1], options[c+3] = options[c+3], options[c+1]
        selections[c+1], selections[c+3] = selections[c+1], selections[c+3]
    end
    return false
end

menu = ToggleMenuMaker(header, settings, icons, 20, keypress=onkey)

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
    test_mod = Base.eval(main, :(module $(gensym()) end))
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
        catch e
            @warn showerror(e)
        end
    catch e
    end
    return test_mod
end

function _quiktest(numlines::Integer, stop::Integer)
    !isinteractive() && error("Julia must be in interactive mode")
    numlines = abs(numlines)
    hist = Base.active_repl.mistate.current_mode.hist
    history = hist.history
    modes = hist.modes
    lines = String[]
    count = 0
    for i = length(history)-1:-1:1
        if !occursin("quiktest(", history[i]) && modes[i] == :julia
            push!(lines, history[i])
            count += 1
        end
        if count ≥ numlines || i ≤ stop
            break
        end
    end
    reverse!(lines)
    println("lines:")
    println(lines...)
    answers = []
    status = []
    main = Base.active_repl.mistate.active_module
    test_mod = make_test_module(main)
    io = IOBuffer()
    for line in lines
        # TODO add lookahead, parse and look for 'ans'
        # if we find it, this line is "ans = " * line
        try
            ans = Base.eval(test_mod, Meta.parse(line))
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
            if occursin(" = ", line)
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
        return nothing
    end
    tests = String[]
    ans_mod = make_test_module(main)
    pad = "        "
    tcount = 0
    for (state, hi_line) in returned
        if state == '\0' || state == 'j'
            continue
        end
        tcount += 1
        line = line_dict[hi_line]
        if state == 'k'
            try
                Base.eval(ans_mod, Meta.parse(line))
                push!(tests, pad, line, "\n")
            catch _
                @warn "this line errors: $line"
                push!(tests, pad, "# error in: " * line, "\n")
            end
        elseif state == 't'
            push!(tests, pad, _testify(ans_mod, line), "\n")
        elseif state == 's'
            push!(tests, pad, _snaptestify(ans_mod, line), "\n")
        elseif state == 'e'
            push!(tests, pad, _errtestify(ans_mod, line), "\n")
        end
    end
    return tcount, join(tests)
end

function quiktest()
    !isinteractive() && error("Julia must be in interactive mode")
    hist = Base.active_repl.mistate.current_mode.hist
    _quiktest(typemax(Int64), hist.start_idx)
end

function quiktest(n::Integer)
    _quiktest(n, 1)
end

# Helper functions

function _testify(mod::Module, e_str::AbstractString)
    expr = (Meta.parse(e_str))
    ans = try
        Base.eval(mod, expr)
    catch err
        @warn "unexpected error in: $e_str"
        if err isa LoadError
            return "# unexpected error: " * string(striplines(:(@test_throws $(wrong_error(err)) eval($expr))))
        else
            return "# unexpected error: " * string(striplines(:(@test_throws $(wrong_error(err)) $expr)))
        end
    end
    if ans isa Symbol
        ans = QuoteNode(ans)
    end
    string(striplines(:(@test $expr !== $ans)))
end

function _errtestify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    try
        ans = Base.eval(mod, expr)
        @warn "no error in: $e_str"
        return "# No error: " * string(striplines(:(@test $expr !== $ans)))
    catch err
        return _errorize(err, expr)
    end
end

function _snaptestify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    ans = try
        Base.eval(mod, expr)
    catch err
        @warn "can't snaptest an error, throws $(typeof(err)): $e_str"
        return "# Unexpected error: " * _errorize(ans, err)
    end
    if ans isa AbstractString
        ans_str = ans
    else
        ans_str = repr(ans)
    end
    string(striplines(:(@test repr($expr) == "snap!" * $ans_str)))
end

errdict = Dict()

function allsubtypes(T::Any, v=[])
    push!(v, T)
    for U in subtypes(T)
        allsubtypes(U, v)
    end
    return v
end

let errvec = collect(allsubtypes(Exception))
    errdict[errvec[begin]] = errvec[end]
    for i = Iterators.drop(eachindex(errvec), 1)
        errdict[errvec[i]] = errvec[i-1]
    end
end

function wrong_error(e::Exception)
    return errdict[typeof(e)]
end

function _errorize(err::Exception, expr)
    if err isa LoadError
        return string(striplines(:(@test_throws $(wrong_error(err)) eval($expr))))
    else
        return string(striplines(:(@test_throws $(wrong_error(err)) $expr)))
    end
end

end  # module QuikTest
