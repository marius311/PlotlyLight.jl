
#-----------------------------------------------------------------------------# json
function json_join(io::IO, itr, sep, left, right)
    print(io, left)
    for (i, item) in enumerate(itr)
        i == 1 || print(io, sep)
        json(io, item)
    end
    print(io, right)
end

json(io::IO, x) = json_join(io, x, ',', '[', ']')  # ***FALLBACK METHOD***

struct JSON{T}
    x::T
end
json(io::IO, x::JSON) = print(io, x.x)


json(x) = sprint(json, x)
json(io::IO, args...) = foreach(x -> json(io, x), args)

# Strings
json(io::IO, x::Union{AbstractChar, AbstractString, Symbol}) = print(io, '"', x, '"')
json(io::IO, x::DateTime) = json(io, Dates.format(x, "YYYY-mm-dd HH:MM:SS"))
json(io::IO, x::Date) = json(io, Dates.format(x, "YYYY-mm-dd"))

# Numbers
json(io::IO, x::Real) = isfinite(x) ? print(io, x) : print(io, "null")
json(io::IO, x::Rational) = json(io, float(x))

# Nulls
json(io::IO, ::Union{Missing, Nothing}) = print(io, "null")

# Bools
json(io::IO, x::Bool) = print(io, x ? "true" : "false")

# Arrays
_json_generic_arr(io::IO, x::AbstractVector) = json_join(io, x, ',', '[', ']')
_json_generic_arr(io::IO, x::AbstractArray) = json(io, eachslice(x; dims=1))
json(io::IO, x::AbstractVector) = _json_generic_arr(io, x)
json(io::IO, x::AbstractArray) = _json_generic_arr(io, x)

# Objects
json(io::IO, x::Pair) = json(io, x.first, JSON(':'), x.second)
json(io::IO, x::Union{NamedTuple, AbstractDict}) = json_join(io, pairs(x), ',', '{', '}')



# Compress certain array types using bdata format (decoded by plotly-three.js)

const _dtype_map = Dict(
    Float32 => "f4", Float64 => "f8",
    Int8 => "i1", UInt8 => "u1",
    Int16 => "i2", UInt16 => "u2",
    Int32 => "i4", UInt32 => "u4",
)

json(io::IO, arr::AbstractVector{<:AbstractFloat}) = _json_num_arr(io, arr)
json(io::IO, arr::AbstractMatrix{<:AbstractFloat}) = _json_num_arr(io, arr)
json(io::IO, arr::AbstractVector{<:Integer}) = _json_num_arr(io, arr)
json(io::IO, arr::AbstractMatrix{<:Integer}) = _json_num_arr(io, arr)

function _to_js_eltype(arr::AbstractArray{<:AbstractFloat})
    # be opinionated and cap at Float32, which should be enough for
    # plotting, halving filesize vs Float64
    T = (eltype(arr) == Float16) ? Float16 : Float32
    return convert(AbstractArray{T}, arr)
end

function _to_js_eltype(arr::AbstractArray{<:Integer})
    # find the smallest integer type that can represent the data
    mn, mx = extrema(arr)
    types = (UInt8, Int8, UInt16, Int16, UInt32, Int32)
    i = findfirst(t -> mn >= typemin(t) && mx <= typemax(t), types)
    isnothing(i) && error("Integer values in plot data are too large to fit in UInt32 or Int32.")
    T = types[i]
    return convert(AbstractArray{T}, arr)
end

function _encode_and_maybe_compress(dat::Vector{UInt8})
    if settings.compress
        dat = transcode(ZlibCompressor, dat)
    end
    return base64encode(dat)
end

function _json_num_arr(io::IO, arr)
    js_arr = _to_js_eltype(arr)
    d = Dict{String,Any}(
        "dtype" => _dtype_map[eltype(js_arr)],
        "bdata" => _encode_and_maybe_compress(Vector(reinterpret(UInt8, view(transpose(js_arr), :)))),
        "shape" => size(js_arr)
    )
    if settings.compress
        d["compress"] = "zlib"
    end
    json(io, d)
end

function json(io::IO, arr::AbstractVector{<:AbstractString})
    d = Dict{String,Any}(
        "dtype" => "str",
        "bdata" => _encode_and_maybe_compress(Vector{UInt8}(join(arr))),
        "blen" => collect(sizeof.(arr))
    )
    if settings.compress
        d["compress"] = "zlib"
    end
    json(io, d)
end