module QuikTest

using ToggleMenus

import REPL.TerminalMenus: request

export menu, quiktest # for now

const header::String = "Press t for test (✅), s for snapshot (📸) g for garbage (🗑 ), G to clear"
const settings::Vector{Char} = ['t', 's', 'g']
const icons::Vector{String} = ["✅", "📸", "🗑 "]

function onkey(menu::ToggleMenu, i::UInt32)
    if Char(i) == 'G'
        selected = copy(menu.selections)
        removals = []
        for (idx, selected) in menu.selections |> enumerate
            if selected == 'g'
                push!(removals, idx)
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

function quiktest()
    hist = Base.active_repl.mistate.current_mode.hist
    history = hist.history
    modes = hist.modes
    lines = String[]
    println("start $(hist.start_idx) cur $(hist.cur_idx) last $(hist.last_idx) ")
    for i = hist.start_idx+1:length(history)-1
        if !occursin("quiktest(", history[i]) && modes[i] == :julia
            push!(lines, history[i])
        end
    end
    request(menu(lines))
end

end  # module QuikTest
