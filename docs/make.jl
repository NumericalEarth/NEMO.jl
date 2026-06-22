using NEMO
using Documenter
using Literate

#####
##### Literate examples
#####

struct Example
    title    :: String
    basename :: String
end

const EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")
const OUTPUT_DIR   = joinpath(@__DIR__, "src", "literated")
mkpath(OUTPUT_DIR)

examples = [
    Example("ORCA2_ICE smoke test", "orca2_ice"),
    Example("Regional Atlantic Simulation", "amm12_regional_simulation").
    Example("Channel Simulation", "channel_step"),
    Example("Julia forced Channel Simulation", "forcing_from_julia")
]

# Skip the heavy literate build (clone NEMO + build + 700MB download + step) unless
# explicitly asked for, so doctest-only or quick prose-only iterations are fast.
build_examples = get(ENV, "NEMO_BUILD_EXAMPLES", "true") == "true"

if build_examples
    for example in examples
        script_path = joinpath(EXAMPLES_DIR, example.basename * ".jl")
        run(`$(Base.julia_cmd()) --color=yes --project=$(dirname(Base.active_project())) $(joinpath(@__DIR__, "literate.jl")) $script_path $OUTPUT_DIR`)
    end
end

#####
##### Documenter
#####

format = Documenter.HTML(collapselevel = 2,
                         size_threshold = nothing,
                         canonical = "https://numericalearth.github.io/NEMO.jl/stable/")

examples_pages = build_examples ?
    [ex.title => joinpath("literated", ex.basename * ".md") for ex in examples] :
    Pair{String, String}[]

pages = Any[
    "Home"          => "index.md",
    "Usage"         => "usage.md",
    "Architecture"  => "architecture.md",
]
isempty(examples_pages) || push!(pages, "Examples" => examples_pages)
push!(pages, "Library" => [
    "Contents"       => "library/outline.md",
    "Public"         => "library/public.md",
    "Private"        => "library/internals.md",
    "Function index" => "library/function_index.md",
])

makedocs(; sitename = "NEMO.jl",
         format,
         pages,
         modules  = [NEMO],
         clean    = true,
         warnonly = [:cross_references, :missing_docs],
         checkdocs = :exports)

#####
##### Deploy
#####

include("deploy.jl")
