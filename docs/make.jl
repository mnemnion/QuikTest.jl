using QuikTest
using Documenter

DocMeta.setdocmeta!(QuikTest, :DocTestSetup, :(using QuikTest); recursive=true)

makedocs(;
    modules=[QuikTest],
    authors="Sam Atman <atmanistan@gmail.com> and contributors",
    sitename="QuikTest.jl",
    format=Documenter.HTML(;
        canonical="https://mnemnion.github.io/QuikTest.jl",
        edit_link="trunk",
        assets=String[],
    ),
    pages=[
        "QuikTest" => "index.md",
        "Docstrings" => "docstrings.md",
    ],
)

deploydocs(;
    repo="github.com/mnemnion/QuikTest.jl",
    devbranch="trunk",
)
