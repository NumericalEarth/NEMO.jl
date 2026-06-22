const forcing_fields = (
    (name = :zonal_wind_stress,      rank = 2, element_type = Float64, readwrite = true),
    (name = :meridional_wind_stress, rank = 2, element_type = Float64, readwrite = true),
    (name = :nonsolar_heat_flux,     rank = 2, element_type = Float64, readwrite = true),
    (name = :solar_radiation,        rank = 2, element_type = Float64, readwrite = true),
    (name = :freshwater_flux,        rank = 2, element_type = Float64, readwrite = true),
    (name = :salt_flux,              rank = 2, element_type = Float64, readwrite = true),
)

for field in forcing_fields
    define_field_accessor(field.name, field.rank, field.element_type, field.readwrite)
end
