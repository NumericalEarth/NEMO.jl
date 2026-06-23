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
    Example("Regional Atlantic Simulation", "amm12_regional_simulation"),
    Example("Channel Simulation", "channel_step"),
    Example("Julia forced Channel Simulation", "forcing_from_julia")
]

# The example pages are pre-rendered locally (where NEMO can be cloned, built, and run) into
# `docs/src/literated/` and committed; CI just includes them. Regenerating requires the full NEMO build
# (clone + compile + GBs of inputs + run), so it only happens when NEMO_BUILD_EXAMPLES=true — e.g. locally,
# `NEMO_BUILD_EXAMPLES=true julia --project=docs docs/make.jl`.
build_examples = get(ENV, "NEMO_BUILD_EXAMPLES", "false") == "true"

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

# Include every example page whose rendered markdown is present in docs/src/literated/. A missing page
# means it has not been pre-rendered yet — warn rather than fail the whole build.
examples_pages = Pair{String, String}[]
for example in examples
    if isfile(joinpath(OUTPUT_DIR, example.basename * ".md"))
        push!(examples_pages, example.title => joinpath("literated", example.basename * ".md"))
    else
        @warn "No rendered markdown for example; run with NEMO_BUILD_EXAMPLES=true to generate it" example.basename
    end
end

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
