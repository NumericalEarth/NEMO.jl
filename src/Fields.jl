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
                           array::Array{T}, expected_shape::Tuple, name::AbstractString) where T
    check_array_shape(array, expected_shape, name)
    ccall(library_symbol(lib, symbol), Cvoid, (Ref{T},), array)
    return array
end

"""
    define_field_accessor(name, rank, element_type, readwrite)

Generate (and export) the `get_\$name!` accessor — and, when `readwrite`, the
matching `set_\$name!` — that bridges the Julia array to NEMO's
`nemo_get_\$name` / `nemo_set_\$name` symbols. `rank` selects the 2D or 3D
interior shape and `element_type` is the Julia element type the symbol exchanges
(`Float64` for the C `double` buffers, `Int32` for integer fields).
"""
function define_field_accessor(name::Symbol, rank::Integer, element_type::DataType, readwrite::Bool)
    description = replace(string(name), "_" => " ")
    size_function = rank == 3 ? interior_size_3d : interior_size_2d
    get_name = Symbol(:get_, name, :!)
    @eval begin
        $get_name(lib::NemoLibrary, array::Array{$element_type, $rank}) =
            call_array_in_out(lib, $(QuoteNode(Symbol(:nemo_get_, name))), array, $size_function(lib), $description)
        export $get_name
    end
    if readwrite
        set_name = Symbol(:set_, name, :!)
        @eval begin
            $set_name(lib::NemoLibrary, array::Array{$element_type, $rank}) =
                call_array_in_out(lib, $(QuoteNode(Symbol(:nemo_set_, name))), array, $size_function(lib), $description)
            export $set_name
        end
    end
    return nothing
end

const state_fields = (
    (name = :temperature,          rank = 3, element_type = Float64, readwrite = true),
    (name = :salinity,             rank = 3, element_type = Float64, readwrite = true),
    (name = :zonal_velocity,       rank = 3, element_type = Float64, readwrite = true),
    (name = :meridional_velocity,  rank = 3, element_type = Float64, readwrite = true),
    (name = :vertical_velocity,    rank = 3, element_type = Float64, readwrite = false),
    (name = :sea_surface_height,   rank = 2, element_type = Float64, readwrite = true),
    (name = :cell_longitude,       rank = 2, element_type = Float64, readwrite = false),
    (name = :cell_latitude,        rank = 2, element_type = Float64, readwrite = false),
    (name = :cell_depth,           rank = 3, element_type = Float64, readwrite = false),
    (name = :cell_zonal_size,      rank = 2, element_type = Float64, readwrite = false),
    (name = :cell_meridional_size, rank = 2, element_type = Float64, readwrite = false),
    (name = :bottom_level_index,   rank = 2, element_type = Int32,   readwrite = false),
)

for field in state_fields
    define_field_accessor(field.name, field.rank, field.element_type, field.readwrite)
end

@doc """
    get_temperature!(lib, array_3d)
    set_temperature!(lib, array_3d)

Access NEMO's active temperature tracer. Under EOS-80 (`ln_eos80 = .true.`)
this is potential temperature in °C; under TEOS-10 (`ln_teos10 = .true.`) it
is Conservative Temperature in °C. The same memory slot in NEMO's `ts` array
holds whichever variable the equation of state expects.
""" get_temperature!
