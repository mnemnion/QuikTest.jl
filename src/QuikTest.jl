module QuikTest

import InteractiveUtils: clipboard
import MacroTools: rmlines
import REPL.TerminalMenus: request
import Term: apply_style, highlight_syntax

using ToggleMenus

export menu, quiktest # for now

head = ("[{bold gold1}k{/bold gold1}]eep (🧿), [{bold gold1}j{/bold gold1}]unk (🗑 ), [{bold gold1}t{/bold gold1}]est (✅), [{bold gold1}s{/bold gold1}]napshot (📸)",
       "[{bold gold1}U{/bold gold1}]p, [{bold gold1}D{/bold gold1}]own, {bold gold1}J{/bold gold1} to clear")
const header = apply_style(join(head, "\n"))
const settings::Vector{Char} = ['k', 'j', 't', 's']
const icons::Vector{String} = ["🧿", "🗑 ", "✅", "📸"]

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

menu = ToggleMenuMaker(header, settings, icons, keypress=onkey)

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

function quiktest()
    hist = Base.active_repl.mistate.current_mode.hist
    history = hist.history
    modes = hist.modes
    lines = String[]
    for i = hist.start_idx+1:length(history)-1
        if !occursin("quiktest(", history[i]) && modes[i] == :julia
            push!(lines, history[i])
        end
    end
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
    if all(x -> x[1] == '\0', returned)
        println("quiktest canceled")
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
        println(state)
        line = line_dict[hi_line]
        if state == 'k'
            try
                Base.eval(ans_mod, Meta.parse(line))
            catch e
                error("this line will error: $line")
            end
            push!(tests, pad, line, "\n")
        elseif state == 't'
            push!(tests, pad, _testify(ans_mod, line), "\n")
        elseif state == 's'
            push!(tests, pad, _snaptestify(ans_mod, line), "\n")
        end
    end
    the_test = join(tests)
    the_test |> clipboard
    Base.eval(main, :(latest_test = $(repr(the_test))))
    print("$tcount line test copied to clipboard and assigned to 'latest_test'")
end

function _testify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    ans = try
        Base.eval(mod, expr)
    catch err
        if err isa LoadError
            e = rmlines(expr)
            return string(rmlines(:(@test_throws StackOverflowError eval($e))))
        else
            e = rmlines(expr)
            return string(rmlines(:(@test_throws LoadError $e)))
        end
    end
    e = rmlines(expr)
    string(rmlines(:(@test $e !== $ans)))
end

function _snaptestify(mod::Module, e_str::AbstractString)
    expr = Meta.parse(e_str)
    ans = try
        Base.eval(mod, expr)
    catch e
        error("Can't make a @test_throws snapshot, try [t] ✅: $e")
    end
    e = rmlines(expr)
    if ans isa AbstractString
        ans_str = ans
    else
        ans_str = string(ans)
    end
    string(rmlines(:(@test repr($e) == "📸" * $ans_str)))
end

end  # module QuikTest
