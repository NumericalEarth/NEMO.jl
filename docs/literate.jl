using Literate

script_path   = ARGS[1]
literated_dir = ARGS[2]

@time basename(script_path) Literate.markdown(script_path, literated_dir;
                                              flavor  = Literate.DocumenterFlavor(),
                                              execute = true)
