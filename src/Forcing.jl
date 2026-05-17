get_zonal_wind_stress!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_zonal_wind_stress, array, interior_size_2d(lib), "zonal wind stress")

set_zonal_wind_stress!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_zonal_wind_stress, array, interior_size_2d(lib), "zonal wind stress")

get_meridional_wind_stress!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_meridional_wind_stress, array, interior_size_2d(lib), "meridional wind stress")

set_meridional_wind_stress!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_meridional_wind_stress, array, interior_size_2d(lib), "meridional wind stress")

get_nonsolar_heat_flux!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_nonsolar_heat_flux, array, interior_size_2d(lib), "nonsolar heat flux")

set_nonsolar_heat_flux!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_nonsolar_heat_flux, array, interior_size_2d(lib), "nonsolar heat flux")

get_solar_radiation!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_solar_radiation, array, interior_size_2d(lib), "solar radiation")

set_solar_radiation!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_solar_radiation, array, interior_size_2d(lib), "solar radiation")

get_freshwater_flux!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_freshwater_flux, array, interior_size_2d(lib), "freshwater flux")

set_freshwater_flux!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_freshwater_flux, array, interior_size_2d(lib), "freshwater flux")

get_salt_flux!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_get_salt_flux, array, interior_size_2d(lib), "salt flux")

set_salt_flux!(lib::NemoLibrary, array::Array{Float64, 2}) =
    call_array_in_out(lib, :nemo_set_salt_flux, array, interior_size_2d(lib), "salt flux")
