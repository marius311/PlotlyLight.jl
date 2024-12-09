
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

# Numbers
json(io::IO, x::Real) = isfinite(x) ? print(io, x) : print(io, "null")
json(io::IO, x::Rational) = json(io, float(x))

# Nulls
json(io::IO, ::Union{Missing, Nothing}) = print(io, "null")

# Bools
json(io::IO, x::Bool) = print(io, x ? "true" : "false")

# Arrays
json(io::IO, x::AbstractVector) = json_join(io, x, ',', '[', ']')
json(io::IO, x::AbstractArray) = json(io, eachslice(x; dims=1))

# Objects
json(io::IO, x::Pair) = json(io, x.first, JSON(':'), x.second)
json(io::IO, x::Union{NamedTuple, AbstractDict}) = json_join(io, pairs(x), ',', '{', '}')



# Compress certain array types for some (huge) space savings for large arrays

json_compression_src_inject = [
    h.script(src="https://cdn.jsdelivr.net/npm/fflate@0.8.2/umd/index.js"),
    h.script(raw"""
    function numArrFromBase64(T, base64, ...dims) {
        arr = new T(fflate.unzlibSync(Uint8Array.from(atob(base64), c => c.charCodeAt(0))).buffer)
        if (dims.length) {
            if (arr.length != dims.reduce((a, b) => a * b)) {
                throw new Error(`Invalid array size for dimensions. Array size: ${arr.length}, Dimensions: ${dims.join('x')}`)
            }
            arr2d = [];
            for (let i = 0; i < arr.length; i += dims[0]) {
                arr2d.push(arr.slice(i, i + dims[0]));
            }
            return arr2d;
        } else {
            return arr;
        }
    }
    function strVecFromBase64(base64, lens) {
        strs = fflate.strFromU8(fflate.unzlibSync(Uint8Array.from(atob(base64), c => c.charCodeAt(0))));
        arr = [];
        cur = 0;
        for (var i = 0; i < lens.length; i++) {
            arr.push(strs.slice(cur, cur + lens[i]));
            cur += lens[i];
        }
        return arr;
    }
    """)
]

function json(io::IO, arr::AbstractVector{T}) where {T<:Union{Float32,Float64}}
    # be opinionated and assume Float32 is enough for plotting, halving the filesize
    arr_base64 = base64encode(transcode(ZlibCompressor, Vector(reinterpret(UInt8, Float32.(arr[:])))))
    print(io, "numArrFromBase64(Float32Array,'$arr_base64')")
end
function json(io::IO, arr::AbstractArray{T}) where {T<:Union{Float32,Float64}}
    # be opinionated and assume Float32 is enough for plotting, halving the filesize
    arr_base64 = base64encode(transcode(ZlibCompressor, Vector(reinterpret(UInt8, Float32.(arr[:])))))
    dims = join(size(arr), ',')
    print(io, "numArrFromBase64(Float32Array,'$arr_base64',$dims)")
end

function json(io::IO, arr::AbstractVector{<:Integer})
    # find the smallest integer type that can represent the data
    T = arr_base64 = nothing
    for outer T in [UInt8, Int8, UInt16, Int16, UInt32, Int32]
        try
            arr_base64 = base64encode(transcode(ZlibCompressor, Vector(reinterpret(UInt8, T.(arr)))))
            break
        catch
        end
    end
    isnothing(arr_base64) && error("Integer values in plot data are too large to fit in UInt32 or Int32.")
    Tjs = string(T)[1] * lowercase(string(T)[2:end])
    print(io, "numArrFromBase64($(Tjs)Array,'$arr_base64')")
end

function json(io::IO, arr::AbstractVector{<:String})
    # store a (compressed) contatenation of the strings and indices where each element starts
    strdat = base64encode(transcode(ZlibCompressor, join(arr)))
    lens = sprint(io -> json(io, length.(arr)))
    print(io, "strVecFromBase64('$strdat',$lens)")
end