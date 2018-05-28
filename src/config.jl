

struct Config
  spotcolor :: Tuple{Float64, Float64, Float64}
  autospotcolor :: Tuple{Float64, Float64, Float64}
  selectedspotcolor :: Tuple{Float64, Float64, Float64}
  spotradius :: Float64
end

struct Worker
  remote :: Bool
  host :: String
  scriptdir :: String
end


function initmainmenu(build)
  spotradius = slider(1:0.1:6, widget = build["labelSpotRadius"])

  localworker = checkbox(true, widget = build["localWorker"])
  remoteworker = checkbox(false, widget = build["remoteWorker"])

  host = textbox("", widget = build["hostName"], gtksignal=:changed)
  scriptdir = textbox("", widget = build["scriptDir"], gtksignal=:changed)

  foreach(localworker) do loc
    if value(remoteworker) == loc
      push!(remoteworker, !loc)
    end
  end

  foreach(remoteworker) do rem
    if value(localworker) == rem
      push!(localworker, !rem)
    end
    if rem
      setproperty!(host.widget, :sensitive, true)
      setproperty!(scriptdir.widget, :sensitive, true)
    else
      setproperty!(host.widget, :sensitive, false)
      setproperty!(scriptdir.widget, :sensitive, false)
    end
  end

  config = map(spotradius) do radius
    default = (0.1, 0.6, 0.3)
    auto = (0.0, 0.4, 0.7)
    selected = (0.6, 0.3, 0.1)
    return Config(default, auto, selected, radius)
  end


  worker = map(remoteworker, host, scriptdir) do remote, host, dir
    return Worker(remote, host, dir)
  end

  return config, worker
end
