module QuikTest

import Term: highlight_syntax, apply_style
using ToggleMenus

import REPL.TerminalMenus: request

export menu, quiktest # for now

head = ("[{bold gold1}k{/bold gold1}]eep (🧿), [{bold gold1}t{/bold gold1}]est (✅), [{bold gold1}s{/bold gold1}]napshot (📸), [{bold gold1}g{/bold gold1}]arbage (🗑 )",
       "[{bold gold1}U{/bold gold1}]p, [{bold gold1}D{/bold gold1}]own, {bold gold1}G{/bold gold1} to clear")
const header = apply_style(join(head, "\n"))
const settings::Vector{Char} = ['k', 't', 's', 'g']
const icons::Vector{String} = ["🧿", "✅", "📸", "🗑 "]

function onkey(menu::ToggleMenu, i::UInt32)
    options, selections = menu.options, menu.selections
    if Char(i) == 'G'
        selected = copy(selections)
        removals = []
        for (idx, selected) in selections |> enumerate
            if selected == 'g'
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
    # Import existing module namese on a best-effort basis
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
    for (line, answer, state) in zip(lines, answers, status)
        push!(options, highlight_syntax(line))
        if state == :answer
            # cheap heuristic
            if occursin(" = ", line)
                push!(selections, 'k')
            else
                push!(selections, 't')
            end
        else
            push!(selections, 'g')
        end
        push!(options, answer)
        push!(selections, '\0')
    end
    request(menu(options, selections))
end

end  # module QuikTest
