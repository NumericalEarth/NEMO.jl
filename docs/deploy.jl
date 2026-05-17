using Documenter

deploydocs(repo       = "github.com/simone-silvestri/NEMO.jl.git",
           devbranch  = "main",
           target     = "build",
           branch     = "gh-pages",
           versions   = ["stable" => "v^", "dev" => "dev", "v#.#.#" => "v#.#.#"],
           forcepush  = true,
           push_preview = false)
