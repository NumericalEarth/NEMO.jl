using MPI
using NEMO

MPI.Init()

const RANK         = MPI.Comm_rank(MPI.COMM_WORLD)
const SIZE         = MPI.Comm_size(MPI.COMM_WORLD)
const COMMUNICATOR = Int32(MPI.COMM_WORLD.val)

const LIBRARY_PATH  = get(ENV, "NEMO_LIBRARY_PATH",  "/tmp/nemo_julia_build_mpi/libnemo.dylib")
const RUN_DIRECTORY = get(ENV, "NEMO_RUN_DIRECTORY", "/tmp/nemo_julia_build_mpi/run")
const STEPS_TO_RUN  = 5

if RANK == 0
    namelist = read_namelist(joinpath(RUN_DIRECTORY, "namelist_cfg"))
    namelist[:namrun][:nn_itend] = STEPS_TO_RUN
    namelist[:namrun][:nn_stock] = 999999  # disable mid-run restart writes
    write_namelist(joinpath(RUN_DIRECTORY, "namelist_cfg"), namelist)
end
MPI.Barrier(MPI.COMM_WORLD)

library = NemoLibrary(LIBRARY_PATH, RUN_DIRECTORY;
                     verbose = (RANK == 0),
                     mpi_communicator = Int32(COMMUNICATOR))

initialize!(library)

RANK == 0 && @info "after init" rank=RANK size=SIZE dims=library.dimensions

zonal_size      = NEMO.local_zonal_size(library)
meridional_size = NEMO.local_meridional_size(library)
vertical_size   = NEMO.vertical_size(library)
@info "local tile" rank=RANK zonal_size meridional_size vertical_size

temperature = zeros(Float64, zonal_size, meridional_size, vertical_size)

for iteration in 1:STEPS_TO_RUN
    step!(library)
    get_temperature!(library, temperature)
    local_mean  = sum(temperature) / length(temperature)
    global_sum  = MPI.Reduce(local_mean * length(temperature), +, 0, MPI.COMM_WORLD)
    global_size = MPI.Reduce(length(temperature),               +, 0, MPI.COMM_WORLD)
    if RANK == 0
        @info("step",
              iteration = get_iteration_count(library),
              time      = get_simulation_time(library),
              mean_T    = global_sum / global_size)
    end
end

MPI.Barrier(MPI.COMM_WORLD)
finalize!(library)
MPI.Finalize()
