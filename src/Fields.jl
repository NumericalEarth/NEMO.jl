interior_size_2d(lib::NemoLibrary) =
    (local_zonal_size(lib), local_meridional_size(lib))

interior_size_3d(lib::NemoLibrary) =
    (local_zonal_size(lib), local_meridional_size(lib), vertical_size(lib))

function check_array_shape(array::AbstractArray, expected_shape::Tuple, name::AbstractString)
    if size(array) != expected_shape
        throw(DimensionMismatch("Array for $name has shape $(size(array)), expected $expected_shape"))
    end
    return nothing
end

function call_array_in_out(lib::NemoLibrary, symbol::Symbol,
                           array::Array{Float64}, expected_shape::Tuple, name::AbstractString)
    check_array_shape(array, expected_shape, name)
    ccall(library_symbol(lib, symbol), Cvoid, (Ref{Float64},), array)
    return array
end

"""
    get_temperature!(lib, array_3d)
    set_temperature!(lib, array_3d)

Access NEMO's active temperature tracer. Under EOS-80 (`ln_eos80 = .true.`)
this is potential temperature in °C; under TEOS-10 (`ln_teos10 = .true.`) it
is Conservative Temperature in °C. The same memory slot in NEMO's `ts` array
holds whichever variable the equation of state expects.
"""
get_temperature!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_get_temperature, array, interior_size_3d(lib), "temperature")

set_temperature!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_set_temperature, array, interior_size_3d(lib), "temperature")

get_salinity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_get_salinity, array, interior_size_3d(lib), "salinity")

set_salinity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_set_salinity, array, interior_size_3d(lib), "salinity")

get_zonal_velocity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_get_zonal_velocity, array, interior_size_3d(lib), "zonal velocity")

set_zonal_velocity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_set_zonal_velocity, array, interior_size_3d(lib), "zonal velocity")

get_meridional_velocity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_get_meridional_velocity, array, interior_size_3d(lib), "meridional velocity")

set_meridional_velocity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_set_meridional_velocity, array, interior_size_3d(lib), "meridional velocity")

get_vertical_velocity!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_get_vertical_velocity, array, interior_size_3d(lib), "vertical velocity")

get_sea_surface_height!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_sea_surface_height, array, interior_size_2d(lib), "sea surface height")

set_sea_surface_height!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_sea_surface_height, array, interior_size_2d(lib), "sea surface height")

get_cell_longitude!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_cell_longitude, array, interior_size_2d(lib), "cell longitude")

get_cell_latitude!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_cell_latitude, array, interior_size_2d(lib), "cell latitude")

get_cell_depth!(lib::NemoLibrary, array::Array{Float64, 3}) =
    call_array_in_out(lib, :nemo_get_cell_depth, array, interior_size_3d(lib), "cell depth")

get_cell_zonal_size!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_cell_zonal_size, array, interior_size_2d(lib), "cell zonal size")

get_cell_meridional_size!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_cell_meridional_size, array, interior_size_2d(lib), "cell meridional size")

function get_bottom_level_index!(lib::NemoLibrary, array::Array{Int32, 2})
    check_array_shape(array, interior_size_2d(lib), "bottom level index")
    ccall(library_symbol(lib, :nemo_get_bottom_level_index), Cvoid, (Ref{Int32},), array)
    return array
end
