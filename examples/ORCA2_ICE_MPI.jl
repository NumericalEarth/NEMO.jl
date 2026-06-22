using MPI
using NEMO

MPI.Init()

const rank            = MPI.Comm_rank(MPI.COMM_WORLD)
const number_of_ranks = MPI.Comm_size(MPI.COMM_WORLD)
const communicator    = Int32(MPI.COMM_WORLD.val)

const library_path  = get(ENV, "NEMO_LIBRARY_PATH",  "/tmp/nemo_julia_build_mpi/libnemo.dylib")
const run_directory = get(ENV, "NEMO_RUN_DIRECTORY", "/tmp/nemo_julia_build_mpi/run")
const steps_to_run  = 5

if rank == 0
    namelist = read_namelist(joinpath(run_directory, "namelist_cfg"))
    namelist[:namrun][:nn_itend] = steps_to_run
    namelist[:namrun][:nn_stock] = 999999  # disable mid-run restart writes
    write_namelist(joinpath(run_directory, "namelist_cfg"), namelist)
end
MPI.Barrier(MPI.COMM_WORLD)

library = NemoLibrary(library_path, run_directory;
                     verbose = (rank == 0),
                     mpi_communicator = Int32(communicator))

initialize!(library)

rank == 0 && @info "after init" rank=rank size=number_of_ranks dims=library.dimensions

zonal_size      = NEMO.local_zonal_size(library)
meridional_size = NEMO.local_meridional_size(library)
vertical_size   = NEMO.vertical_size(library)
@info "local tile" rank=rank zonal_size meridional_size vertical_size

temperature = zeros(Float64, zonal_size, meridional_size, vertical_size)

for iteration in 1:steps_to_run
    step!(library)
    get_temperature!(library, temperature)
    local_mean  = sum(temperature) / length(temperature)
    global_sum  = MPI.Reduce(local_mean * length(temperature), +, 0, MPI.COMM_WORLD)
    global_size = MPI.Reduce(length(temperature),               +, 0, MPI.COMM_WORLD)
    if rank == 0
        @info("step",
              iteration = get_iteration_count(library),
              time      = get_simulation_time(library),
              mean_T    = global_sum / global_size)
    end
end

MPI.Barrier(MPI.COMM_WORLD)
finalize!(library)
MPI.Finalize()
