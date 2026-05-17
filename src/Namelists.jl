function strip_comment(line::AbstractString)
    index = findfirst('!', line)
    return index === nothing ? line : line[1:prevind(line, index)]
end

function parse_scalar_value(text::AbstractString)
    cleaned = strip(text)
    isempty(cleaned) && return nothing

    if startswith(cleaned, '"') || startswith(cleaned, '\'')
        quote_character = first(cleaned)
        terminator      = findlast(quote_character, cleaned)
        if terminator === nothing || terminator == firstindex(cleaned)
            return cleaned
        end
        return String(cleaned[nextind(cleaned, firstindex(cleaned)):prevind(cleaned, terminator)])
    end

    lower = lowercase(cleaned)
    lower in (".true.", "t", ".t.")  && return true
    lower in (".false.", "f", ".f.") && return false

    integer_value = tryparse(Int, cleaned)
    integer_value !== nothing && return integer_value

    fortran_float = replace(cleaned, r"([0-9])[dD]([+-]?[0-9])" => s"\1e\2")
    float_value   = tryparse(Float64, fortran_float)
    float_value !== nothing && return float_value

    return String(cleaned)
end

function parse_value(text::AbstractString)
    pieces = split(text, ',', keepempty=false)
    parsed = [parse_scalar_value(piece) for piece in pieces if !isempty(strip(piece))]
    return length(parsed) == 1 ? parsed[1] : parsed
end

"""
    read_namelist(filename)

Parse a Fortran namelist file (NEMO `namelist_cfg`, `namelist_ref`, etc.) into
a [`NemoNamelist`](@ref). Comments (`!`), continuation lines, integer / float /
boolean / string / list values, and double-precision `d` exponents are handled.
"""
function read_namelist(filename::AbstractString)
    namelist        = NemoNamelist()
    current_group   = Symbol("")
    current_params  = OrderedDict{Symbol, Any}()
    pending_key     = Symbol("")
    pending_text    = ""
    inside_group    = false

    open(filename) do file
        for raw_line in eachline(file)
            line = strip(strip_comment(raw_line))
            isempty(line) && continue

            if !inside_group
                if startswith(line, '&')
                    current_group  = Symbol(strip(line[2:end]))
                    current_params = OrderedDict{Symbol, Any}()
                    pending_key    = Symbol("")
                    pending_text   = ""
                    inside_group   = true
                end
                continue
            end

            if line == "/" || line == "&end" || line == "&END"
                if pending_key != Symbol("")
                    current_params[pending_key] = parse_value(pending_text)
                end
                push!(namelist.groups, current_group)
                push!(namelist.parameters, current_params)
                inside_group  = false
                pending_key   = Symbol("")
                pending_text  = ""
                continue
            end

            assignment_index = findfirst('=', line)
            if assignment_index === nothing
                pending_text *= " " * line
                continue
            end

            if pending_key != Symbol("")
                current_params[pending_key] = parse_value(pending_text)
            end

            key_text   = strip(line[1:prevind(line, assignment_index)])
            value_text = strip(line[nextind(line, assignment_index):end])
            pending_key  = Symbol(key_text)
            pending_text = value_text
        end
    end

    return namelist
end

format_value(value::Bool)    = value ? ".true." : ".false."
format_value(value::Integer) = string(value)
format_value(value::Real)    = (text = string(value); occursin('.', text) || occursin('e', text) ? text : text * ".")
format_value(value::AbstractString) = "\"" * value * "\""
format_value(value::AbstractVector) = join(format_value.(value), ", ")
format_value(value)          = string(value)

"""
    write_namelist(filename, namelist::NemoNamelist)

Write a `NemoNamelist` back to disk in standard Fortran namelist format
(group, indented `key = value` pairs, terminating `/`).
"""
function write_namelist(filename::AbstractString, namelist::NemoNamelist)
    open(filename, "w") do file
        for (group, parameters) in zip(namelist.groups, namelist.parameters)
            println(file, "&", group)
            for (key, value) in parameters
                println(file, "   ", key, " = ", format_value(value))
            end
            println(file, "/")
            println(file)
        end
    end
    return filename
end

function Base.getindex(namelist::NemoNamelist, group::Symbol)
    index = findfirst(==(group), namelist.groups)
    index === nothing && throw(KeyError(group))
    return namelist.parameters[index]
end

function Base.haskey(namelist::NemoNamelist, group::Symbol)
    return findfirst(==(group), namelist.groups) !== nothing
end
