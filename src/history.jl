
abstract type Action end

struct History
  actions :: Vector{Action}
end

function Base.push!(history :: Signal{History}, a :: Action)
  push!(history, History([value(history).actions; a]))
end

function inithistory()
  return Signal(History(Action[]))
end

function initlastaction(widget, history)
  foreach(history) do h
    push!(widget, text(h.actions[end]))
  end
end


struct AddImages <: Action
  imgs :: Vector{String}
end

struct RemoveImages <: Action
  imgs :: Vector{String}
end

struct AddSpot <: Action
  spot :: Tuple{Int, Int}
end

struct RemoveSpot <: Action
  spot :: Tuple{Int, Int}
end

struct MoveSpot <: Action
  from :: Tuple{Int, Int}
  to :: Tuple{Int, Int}
end

struct AddTrainFrame <: Action
  region :: NTuple{4, Int}
end

struct RemoveTrainFrame <: Action
  region :: NTuple{4, Int}
end

struct SaveLabels <: Action end
struct ApplyModelStart <: Action end
struct ApplyModelEnd <: Action end
struct ResetDensity <: Action end

Base.push!(history :: History, a :: Action) = push!(history.actions, a)

text(h :: History) = text(h.actions[end])

text(a :: AddImages) = isempty(a.imgs) ? "" : "Added $(length(a.imgs)) image/s"
text(a :: RemoveImages) = isempty(a.imgs) ? "" : "Removed $(length(a.imgs)) image/s"
text(a :: AddSpot) = "Added spot at $((a.spot[1], a.spot[2]))"
text(a :: RemoveSpot) = "Removed spot at $((a.spot[1], a.spot[2]))"
text(a :: MoveSpot) = "Moved spot from $(a.from) to $(a.to)"
text(a :: AddTrainFrame) = "Added train frame"
text(a :: RemoveTrainFrame) = "Removed train frame"

text(a :: SaveLabels) = "Saved labels"
text(a :: ApplyModelStart) = "Density computation started..."
text(a :: ApplyModelEnd) = "Density computation finished"
text(a :: ResetDensity) = "Density resetted"
