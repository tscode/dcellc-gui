

struct Config
  spotcolor :: Tuple{Float64, Float64, Float64}
  autospotcolor :: Tuple{Float64, Float64, Float64}
  selectedspotcolor :: Tuple{Float64, Float64, Float64}
  spotradius :: Float64
end


function initconfig()
  default = (0.1, 0.6, 0.3)
  auto = (0.3, 0.6, 0.1)
  selected = (0.6, 0.3, 0.1)
  radius = 3.
  return Reactive.Signal(Config(default, auto, selected, radius))
end
