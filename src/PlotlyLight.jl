module PlotlyLight

using Random: randstring
using Downloads: download
using Scratch: get_scratch!

using JSON3
using EasyConfig
using Cobweb
using Cobweb: h
using StructTypes

#-----------------------------------------------------------------------------# exports
export Plot, Config, Preset, settings!

#-----------------------------------------------------------------------------# __init__()
const version = Ref(VersionNumber("0.0.0"))  # Version of Plotly.js currently in use by PlotlyLight
const cdn_url = Ref("")  # URL of Plotly.js currently in use by PlotlyLight
const scratch_dir = Ref("")  # PlotlyLight's scratchspace
const plotlyjs = Ref("")  # Local copy of Plotly.js
const plotlys_dir = Ref("")  # Directory containing local copies of Plotly.js
const templates_dir = Ref("")  # Directory containing local copies of templates
const TEMPLATES = [:ggplot2, :gridon, :plotly, :plotly_dark, :plotly_white, :presentation, :seaborn, :simple_white, :xgridoff, :ygridoff]


function __init__()
    scratch_dir[] = get_scratch!("PlotlyLight")
    plotlyjs[] = joinpath(scratch_dir[], "plotlys", "plotly.min.js")
    plotlys_dir[] = mkpath(joinpath(scratch_dir[], "plotlys"))
    templates_dir[] = mkpath(joinpath(scratch_dir[], "templates"))

    (isempty(readdir(plotlys_dir[])) || isempty(readdir(templates_dir[])) || isempty(readdir(scratch_dir[])) || !isfile(plotlyjs[])) && update!()

    version[] = get_semver(readuntil(plotlyjs[], "*/"))
    cdn_url[] = "https://cdn.plot.ly/plotly-$(version[]).min.js"

    Preset.PlotContainer.auto!()

    @info """


    !!! Attention !!!

    PlotlyLight 0.7 has breaking changes:

    1. No more artifacts.  PlotlyLight now downloads the latest version of Plotly.js and templates at your request.
      - Use `PlotlyLight.update!()` to update Plotly and the templates.

    2. `Defaults` is now a struct rather than a module.  No more messing around with `Ref`s.  Change defaults with `defaults!(reset::Bool; kw...)`.
        - See `?Defaults` and `?defaults!` for more info.
    """
end


#-----------------------------------------------------------------------------# "artifacts"
# PlotlyLight's scratchspace looks like:
# - <UUID>/PlotlyLight/plotlys/plotly-*.*.*.min.js (as well as plotly.min.js)
# - <UUID>/PlotlyLight/templates/*.json
# - <UUID>/PlotlyLight/plotly-schema.json

get_semver(x) = VersionNumber(match(r"v(\d+)\.(\d+)\.(\d+)", x).match[2:end])

function latest_plotlyjs_version()
    content = read(download("https://github.com/plotly/plotly.js/tags"), String)
    return get_semver(content)
end

function download_plotly!(v::VersionNumber = latest_plotlyjs_version())
    @info "PlotlyLight: Downloading Plotly.js v$v"
    file = joinpath(scratch_dir[], "plotlys", "plotly-$v.min.js")
    !isfile(file) && download("https://cdn.plot.ly/plotly-$v.min.js", file)
    cp(file, joinpath(scratch_dir[], "plotlys", "plotly.min.js"); force=true)
    nothing
end

function download_templates!()
    for t in TEMPLATES
        @info "PlotlyLight: Downloading template: $t"
        url = "https://raw.githubusercontent.com/plotly/plotly.py/master/packages/python/plotly/plotly/package_data/templates/$t.json"
        download(url, joinpath(scratch_dir[], "templates", "$t.json"))
    end
    nothing
end

function download_schema!()
    @info "PlotlyLight: Downloading schema"
    download("https://api.plot.ly/v2/plot-schema?format=json&sha1=%27%27", joinpath(scratch_dir[], "plotly-schema.json"))
    nothing
end

function update!(v::VersionNumber = latest_plotlyjs_version())
    download_plotly!(v)
    download_templates!()
    download_schema!()
    version[] = get_semver(readuntil(plotlyjs[], "*/"))
    cdn_url[] = "https://cdn.plot.ly/$version.min.js"
    nothing
end


#-----------------------------------------------------------------------------# Settings
Base.@kwdef mutable struct Settings
    verbose::Bool       = false
    fix_matrix::Bool    = true
    load_plotlyjs       = () -> Cobweb.h.script(src=cdn_url[], charset="utf-8")
    make_container      = (id) -> Cobweb.h.div(; id)
    layout::Config      = Config()
    config::Config      = Config(displaylogo = false)
    iframe::Union{Nothing, Cobweb.IFrame} = nothing
end
function Base.show(io::IO, o::Settings)
    println(io, "PlotlyLight.Settings:")
    printstyled(io, "  • verbose:\n", color=:light_cyan);
    printstyled(io, "      ", o.verbose, '\n', color=:light_black)
    printstyled(io, "  • load_plotlyjs: function()::Cobweb.Node\n", color=:light_cyan)
    printstyled(io, Cobweb.pretty(o.load_plotlyjs(); depth=2), '\n', color=:light_black)
    printstyled(io, "  • make_container: function(id)::Cobweb.Node\n", color=:light_cyan)
    printstyled(io, Cobweb.pretty(o.make_container("[id]"); depth=2), '\n', color=:light_black)
    printstyled(io, "  • layout: \n", color=:light_cyan)
    printstyled(io, "      Config with keys: $(join(repr.(keys(o.layout)), ", "))", '\n', color=:light_black)
    printstyled(io, "  • config: \n", color=:light_cyan)
    printstyled(io, "      Config with keys: $(join(repr.(keys(o.config)), ", "))", '\n', color=:light_black)
    printstyled(io, "  • iframe: \n", color=:light_cyan)
    printstyled(io, "      ", repr(o.iframe), '\n', color=:light_black)
end

DEFAULT_SETTINGS = Settings()

reset!(s::Settings = settings()) = foreach(x -> setfield!(s, x, getfield(Settings(), x)), fieldnames(Settings))

settings() = DEFAULT_SETTINGS

settings!(s = settings(); kw...) = (foreach(kv -> setfield!(s, kv...), kw); s)
settings!(r::Bool; kw...) = (r && reset!(); settings!(; kw...))

#-----------------------------------------------------------------------------# Presets
module Preset
    module Template
        using JSON3, EasyConfig
        import ...settings, ...templates_dir, ...TEMPLATES
        for t in TEMPLATES
            f = Symbol("$(t)!")
            @eval begin
                export $f
                function $f()
                    file = joinpath(templates_dir[], $(string(t)) * ".json")
                    settings().layout.template = open(io -> JSON3.read(io, Config), file)
                end
            end
        end
    end

    module Source
        using Cobweb: h
        import ...settings!, ...cdn_url, ...plotlyjs
        cdn!() = settings!(; load_plotlyjs = () -> h.script(src=cdn_url[], charset="utf-8"))
        local!() = settings!(; load_plotlyjs = () -> h.script(src=plotlyjs[], charset="utf-8"))
        standalone!() = settings!(; load_plotlyjs = () -> h.script(read(plotlyjs[], String), charset="utf-8"))
        none!() = settings!(; load_plotlyjs = () -> "")
    end

    module PlotContainer
        using EasyConfig
        using Cobweb: Cobweb, h
        import ...settings, ...settings!, ...reset!

        fillwindow!(r = true) = settings!(r;
                make_container = id -> h.div(style="height:100vh;width:100vw;", h.div(; id, style="height:100%;width:100%")),
                config = Config(responsive=true)
            )

        responsive!(r = true) = settings!(r;
                make_container = id -> h.div(style="height:100%;", h.div(; id, style="height:100%;")),
                config=Config(responsive=true)
            )

        function iframe!(r = true; height="450px", width="750px", style="resize:both; display:block", kw...)
            fillwindow!(r)
            settings!(false; iframe=Cobweb.IFrame(html""; height, width, style, kw...))
        end

        pluto!(r = true) = settings!(r, config=Config(height="100%", width="100%"))

        function auto!(r = true, io::IO = stdout)
            :pluto in keys(io) ? pluto!(r) :
            :jupyter in keys(io) ? iframe!(r) :
            isinteractive() ? fillwindow!(r) :
            nothing
        end
    end
end

#-----------------------------------------------------------------------------# Plot
"""
    Plot(data, layout=Config(), config=Config())
    Plot(layout=Config(), config=Config(); kw...)

Create a Plotly plot with the given `data` (`Config` or `Vector{Config}`), `layout`, and `config`.
Alternatively, you can create a plot with a single trace by providing the `data` as keyword arguments.

For more info, read the Plotly.js docs: [https://plotly.com/javascript/](https://plotly.com/javascript/).

### Examples

    p = Plot(Config(x=1:10, y=randn(10)))

    p = Plot(; x=1:10, y=randn(10))
"""
mutable struct Plot
    data::Vector{Config}
    layout::Config
    config::Config
    Plot(data::Vector{Config}, layout::Config=Config(), config::Config=Config()) = new(data, layout, config)
end
Plot(data::Config, layout::Config = Config(), config::Config = Config()) = Plot([data], layout, config)
Plot(; layout=Config(), config=Config(), @nospecialize(kw...)) = Plot(Config(kw), Config(layout), Config(config))
(p::Plot)(; @nospecialize(kw...)) = p(Config(kw))
(p::Plot)(data::Config) = (push!(p.data, data); return p)

StructTypes.StructType(::Plot) = StructTypes.Struct()

#-----------------------------------------------------------------------------# Display
function page(o::Plot; remove_margins=false)
    h = Cobweb.h
    return Cobweb.Page(h.html(
        h.head(
            h.meta(charset="utf-8"),
            h.meta(name="viewport", content="width=device-width, initial-scale=1"),
            h.meta(name="description", content="PlotlyLight.jl with Plotly $(version[])"),
            h.title("PlotlyLight.jl with Plotly $(version[])"),
            h.style("body { margin: 0px; }")  # removes scrollbar when in iframe
        ),
        o
    ))
end

Base.display(::Cobweb.CobwebDisplay, o::Plot) = display(Cobweb.CobwebDisplay(), page(o))

Base.show(io::IO, ::MIME"juliavscode/html", o::Plot) = show(io, MIME"text/html"(), o)

function Base.show(io::IO, M::MIME"text/html", o::Plot; setting::Settings = DEFAULT_SETTINGS, id=randstring(10))
    if isnothing(setting.iframe)
        (; data, layout, config) = o
        layout = merge(setting.layout, layout)
        config = merge(setting.config, config)
        setting.fix_matrix && fix_matrix!(data)
        show(io, M, setting.load_plotlyjs())
        show(io, M, setting.make_container(id))
        print(io, "<script>Plotly.newPlot(", repr(id), ", ")
        foreach(x -> (JSON3.write(io, x); print(io, ", ")), (data, layout, config))
        print(io, ")</script>")
    else
        iframe = setting.iframe
        try
            settings!(; iframe=nothing)
            buf = IOBuffer()
            show(buf, M, o; id)
            show(io, M, Cobweb.IFrame(HTML(String(take!(buf))); iframe.kw...))
        finally
            settings!(; iframe)
        end
    end
end

#-----------------------------------------------------------------------------# collectrows
collectrows(x::AbstractMatrix) = collect.(eachrow(x))

fix_matrix!(x::Config) = map(fix_matrix!, values(x))
fix_matrix!(x) = x
fix_matrix!(x::AbstractMatrix) = collect.(eachrow(x))


end # module
