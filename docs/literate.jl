using Literate

script_path   = ARGS[1]
literated_dir = ARGS[2]

@time basename(script_path) Literate.markdown(script_path, literated_dir;
                                              flavor  = Literate.DocumenterFlavor(),
                                              execute = true)

# Documenter serves each page with a pretty URL (literated/<name>/index.html), so a `<source src="x.mp4">`
# in the page resolves relative to literated/<name>/. The examples write their videos with plain filenames
# into the working directory (literated_dir); move them into the matching per-page folder so the references
# resolve in the built site.
page_directory = joinpath(literated_dir, first(splitext(basename(script_path))))
for entry in readdir(literated_dir; join = true)
    if isfile(entry) && endswith(entry, ".mp4")
        mkpath(page_directory)
        mv(entry, joinpath(page_directory, basename(entry)); force = true)
    end
end
