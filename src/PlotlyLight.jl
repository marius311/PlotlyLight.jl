module PlotlyLight

using Artifacts: @artifact_str
using Base64
using Downloads: download
using Dates
using REPL

using JSON3: JSON3
using EasyConfig: Config
using Cobweb: Cobweb, h, IFrame, Node
using CodecZlib

#-----------------------------------------------------------------------------# exports
export Config, preset, Plot, plot

#-----------------------------------------------------------------------------# __init__
include("json.jl")

artifact(x...) = joinpath(artifact"plotly_artifacts", x...)

function __init__()
end

#-----------------------------------------------------------------------------# plotly::PlotlyArtifacts
Base.@kwdef struct PlotlyArtifacts
    version::VersionNumber  = VersionNumber(read(artifact("version.txt"), String))
    url::String             = "https://cdn.plot.ly/plotly-$version.min.js"
    path::String            = artifact("plotly.min.js")
    schema::JSON3.Object    = JSON3.read(read(artifact("plot-schema.json"), String))
    templates::Dict{String,String} = Dict(t => artifact("templates", t) for t in readdir(artifact("templates")))
end
Base.show(io::IO, p::PlotlyArtifacts) = print(io, "PlotlyArtifacts: v$(p.version)")
plotly::PlotlyArtifacts = PlotlyArtifacts()

#-----------------------------------------------------------------------------# Settings
Base.@kwdef mutable struct Settings
    src::Node               = h.script(src=plotly.url, charset="utf-8")
    div::Node               = h.div(; class="plotlylight-plot-div")
    layout::Config          = Config()
    config::Config          = Config(responsive=true, displaylogo=false)
    reuse_preview::Bool     = true
    page_css::Cobweb.Node   = h.style("html, body { padding: 0px; margin: 0px; }")
    use_iframe::Bool        = false
    iframe_style            = "display:block; border:none; min-height:350px; min-width:350px; width:100%; height:100%"
    src_inject::Vector      = []
    compress::Bool          = false
end
settings::Settings = Settings()

function Settings(s::Settings; kw...)
    s2 = deepcopy(s)
    for (k, v) in kw
        setfield!(s2, k, v)
    end
    return s2
end

function with_settings(f; kw...)
    old = settings
    try
        global settings = Settings(settings; kw...)
        f(settings)
    finally
        global settings = old
    end
end

get_src_inject(s::Settings) = s.src_inject

#-----------------------------------------------------------------------------# utils/other
attributes(t::Symbol) = plotly.schema.traces[t].attributes
check_attribute(trace, attr::Symbol) = haskey(attributes(Symbol(trace)), attr) || @warn("`$trace` does not have attribute `$attr`.")
check_attributes(trace; kw...) = foreach(k -> check_attribute(Symbol(trace), k), keys(kw))

#-----------------------------------------------------------------------------# Plot
mutable struct Plot
    data::Vector{Config}
    layout::Config
    config::Config
    frames::Vector{Config}
    Plot(data::AbstractVector=Config[], layout = Config(), config = Config(); frames=Config[]) = new(Config.(data), Config(layout), Config(config), Config.(frames))
    Plot(data, layout = Config(), config = Config(); frames=Config[]) = new([Config(data)], Config(layout), Config(config), Config.(frames))
end

Base.:(==)(a::Plot, b::Plot) = all(getfield(a,f) == getfield(b,f) for f in fieldnames(Plot))

save(p::Plot, file::AbstractString) = open(io -> print(io, html_page(p)), file, "w")
save(file::AbstractString, p::Plot) = save(p, file)

(p::Plot)(; kw...) = p(Config(kw))
(p::Plot)(data::Config) = (push!(p.data, data); return p)
(p::Plot)(p2::Plot) = merge!(p, p2)

Base.getproperty(p::Plot, x::Symbol) = x in fieldnames(Plot) ? getfield(p, x) : (; kw...) -> p(plot(; type=x, kw...))
Base.propertynames(p::Plot) = vcat(fieldnames(Plot)..., keys(plotly.schema.traces)...)

function _merge_frame_pair(af::Config, bf::Config, na::Int, nb::Int)
    ad = haskey(af, :data) ? af.data : [Config() for _ in 1:na]
    bd = haskey(bf, :data) ? bf.data : [Config() for _ in 1:nb]
    mf = Config()
    mf.data = vcat(ad, bd)
    for f in (af, bf), k in keys(f)
        k === :data && continue
        mf[k] = f[k]
    end
    return mf
end

_frame_name(f::Config) = haskey(f, :name) ? f.name : nothing

function _merge_frames!(a::Plot, b::Plot, na::Int, nb::Int)
    isempty(a.frames) && isempty(b.frames) && return
    if isempty(a.frames)
        # pad b's frames with empty configs for a's traces
        for f in b.frames
            bd = haskey(f, :data) ? f.data : [Config() for _ in 1:nb]
            f.data = vcat([Config() for _ in 1:na], bd)
        end
        append!(a.frames, b.frames)
        return
    end
    if isempty(b.frames)
        # pad a's frames with empty configs for b's traces
        for f in a.frames
            ad = haskey(f, :data) ? f.data : [Config() for _ in 1:na]
            f.data = vcat(ad, [Config() for _ in 1:nb])
        end
        return
    end
    # both have frames — must be same length
    length(a.frames) == length(b.frames) || error("Cannot merge plots with different numbers of frames ($(length(a.frames)) vs $(length(b.frames)))")
    # match by name if frames are named, otherwise positional
    a_named = _frame_name(a.frames[1]) !== nothing
    b_named = _frame_name(b.frames[1]) !== nothing
    if a_named && b_named
        b_by_name = Dict(_frame_name(f) => f for f in b.frames)
        for i in eachindex(a.frames)
            name = _frame_name(a.frames[i])
            bf = get(b_by_name, name, nothing)
            bf === nothing && error("Frame $(repr(name)) not found in second plot")
            a.frames[i] = _merge_frame_pair(a.frames[i], bf, na, nb)
        end
    else
        for i in eachindex(a.frames)
            a.frames[i] = _merge_frame_pair(a.frames[i], b.frames[i], na, nb)
        end
    end
end

function Base.merge!(a::Plot, b::Plot)
    na = length(a.data)
    nb = length(b.data)
    append!(a.data, b.data)
    merge!(a.layout, b.layout)
    merge!(a.config, b.config)
    _merge_frames!(a, b, na, nb)
    return a
end

#-----------------------------------------------------------------------------# plot
function plot(; layout = Config(), config=Config(), frames=Config[], type=:scatter, kw...)
    check_attributes(type; kw...)
    data = isempty(kw) ? Config[] : [Config(; type, kw...)]
    Plot(data, layout, config; frames)
end
Base.propertynames(::typeof(plot)) = keys(plotly.schema.traces)
Base.getproperty(::typeof(plot), type::Symbol) = (; kw...) -> plot(; type=type, kw...)


#-----------------------------------------------------------------------------# NewPlotScript
# PlotlyX representation of: <script>Plotly.newPlot("$id", $data, $layout, $config)</script>
struct NewPlotScript
    plot::Plot
    settings::Settings
    id::String
end
function Base.show(io::IO, ::MIME"text/html", o::NewPlotScript)
    layout = merge(o.settings.layout, o.plot.layout)
    config = merge(o.settings.config, o.plot.config)
    frames = o.plot.frames
    if isempty(frames)
        print(io, "<script>Plotly.newPlot(\"", o.id, "\",")
        json(io, o.plot.data); print(io, ',')
        json(io, layout); print(io, ',')
        json(io, config)
        print(io, ")</script>")
    else
        print(io, "<script>Plotly.newPlot(\"", o.id, "\",{data:")
        json(io, o.plot.data); print(io, ",layout:")
        json(io, layout); print(io, ",config:")
        json(io, config); print(io, ",frames:")
        json(io, frames)
        print(io, "})</script>")
    end
end

#-----------------------------------------------------------------------------# display
rand_id() = "plotlyx-" * join(rand('a':'z', 10))

function html_div(o::Plot, id=rand_id())
    h.div(class="plotlylight-parent", get_src_inject(settings)..., settings.src, settings.div(; id), NewPlotScript(o, settings, id))
end

function html_page(o::Plot, id=rand_id())
    h.html(
        h.head(
            h.meta(charset="utf-8"),
            h.meta(name="viewport", content="width=device-width, initial-scale=1"),
            h.meta(name="description", content="PlotlyLight.jl Plot"),
            h.title("PlotlyLight.jl"),
            settings.page_css,
            get_src_inject(settings)...,
            settings.src
        ),
        h.body(h.div(class="plotlylight-parent", settings.div(; id), NewPlotScript(o, settings, id)))
    )
end

function html_iframe(o::Plot, id=rand_id(), kw...)
    with_settings() do s
        s.div.style = "height:100vh; width:100vw"
        Cobweb.IFrame(html_page(o, id); style=s.iframe_style, kw...)
    end
end

function Base.show(io::IO, ::MIME"text/html", o::Plot)
    (get(io, :jupyter, false) || settings.use_iframe) ?
        show(io, MIME("text/html"), html_iframe(o)) :
        show(io, MIME("text/html"), html_div(o))
end
Base.show(io::IO, ::MIME"juliavscode/html", o::Plot) = show(io, MIME("text/html"), o)
Base.show(io::IO, ::MIME"text/plain", o::Plot) = print(io, "PlotlyLight.jl Plot")

Base.display(::REPL.REPLDisplay, o::Plot) = Cobweb.preview(html_page(o); reuse=settings.reuse_preview)


#-----------------------------------------------------------------------------# preset
# `preset_template_<X>` overwrites `settings.layout.template`
# `preset_src_<X>` overwrites `settings.src`
# `preset_display_<X>` overwrites `settings.config.responsive`, `settings.div`, `settings.layout.[width, height]`

template!(t) = (settings.layout.template = JSON3.read(read(plotly.templates["$t.json"])); nothing)

preset = (
    template = (
        none!           = () -> (haskey(settings.layout, :template) && delete!(settings.layout, :template); nothing),
        ggplot2!        = () -> template!(:ggplot2),
        gridon!         = () -> template!(:gridon),
        plotly!         = () -> template!(:plotly),
        plotly_dark!    = () -> template!(:plotly_dark),
        plotly_white!   = () -> template!(:plotly_white),
        presentation!   = () -> template!(:presentation),
        seaborn!        = () -> template!(:seaborn),
        simple_white!   = () -> template!(:simple_white),
        xgridoff!       = () -> template!(:xgridoff),
        ygridoff!       = () -> template!(:ygridoff)
    ),
    source = (
        none!       = () -> (settings.src = h.div("No script due to `PlotlyLight.src_none!`", style="display:none;"); nothing),
        cdn!        = () -> (settings.src = h.script(src=plotly.url, charset="utf-8"); nothing),
        local!      = () -> (settings.src = h.script(src=plotly.path, charset="utf-8"); nothing),
        standalone! = () -> (settings.src = h.script(read(plotly.path, String), charset="utf-8"); nothing)
    ),
    display = (
        fullscreen!     = () -> (settings.div.style = "height:100vh; width:100vw"),
        mathjax!        = () -> (push!(settings.src_inject, h.script(src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-svg.js"))),
        compress!       = (enabled=true) -> (settings.compress = enabled)
    )
)

end  # PlotlyLight module
