module QuikTest

import Term: highlight_syntax, apply_style
using ToggleMenus

import REPL.TerminalMenus: request

export menu, quiktest # for now

head = "Press {bold gold1}t{/bold gold1} for test (✅), {bold gold1}s{/bold gold1} for snapshot (📸) {bold gold1}g{/bold gold1} for garbage (🗑 ), {bold gold1}G{/bold gold1} to clear"
header = apply_style(head)
const settings::Vector{Char} = ['t', 's', 'g']
const icons::Vector{String} = ["✅", "📸", "🗑 "]

function onkey(menu::ToggleMenu, i::UInt32)
    if Char(i) == 'G'
        selected = copy(menu.selections)
        removals = []
        for (idx, selected) in menu.selections |> enumerate
            if selected == 'g'
                push!(removals, idx)
                push!(removals, idx + 1)
            end
        end
        for remove in reverse(removals)
            deleteat!(menu.options, remove)
            deleteat!(menu.selections, remove)
        end
        for _ = 1:length(removals)
            push!(menu.options, "")
            push!(menu.selections, '\0')
        end
    end
    if isempty(menu.options)
        return true
    else
        return false
    end
end

menu = ToggleMenuMaker(header, settings, icons, keypress=onkey)

function make_test_module(main::Module)
    module_names = Symbol[]
    for name in names(main; all=true, imported=true)
        # Check if the binding is a module
        if isdefined(Main, name)
            val = Base.eval(Main, name)
            if val ≠ main && val isa Module
                push!(module_names, name)
            end
        end
    end
    test_mod = Base.eval(main, :(module $(gensym()) end))
    for name in module_names
        try Base.eval(test_mod, :(using $(name)))
        catch e
        end
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
            push!(selections, 't')
        else
            push!(selections, 'g')
        end
        push!(options, answer)
        push!(selections, '\0')
    end
    request(menu(options, selections))
end

end  # module QuikTest
