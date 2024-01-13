module QuikTest

using ToggleMenus

import REPL.TerminalMenus: move_up!

export menu  # for now

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

end
