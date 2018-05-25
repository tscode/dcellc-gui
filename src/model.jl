
# ---------------------------------------------------------------------------- #
# Struct for dynamically enhanceable dropdown menues
# (the default dropdown provided by GtkReactive is not dynamically alterable)

struct ModelDropdown
  signal :: Signal{String}
  widget :: GtkComboBoxTextLeaf
  int2str :: Dict{Int,String}
  str2int :: Dict{String,Int}
end

function pushchoice!(m::ModelDropdown, c::String)
  push!(m.widget, c)
  k = length(m.str2int) + 1
  m.str2int[c] = k
  m.int2str[k] = c
end

function deletechoice!(m::ModelDropdown, c::String)
  k = m.str2int[c]
  delete!(m.widget, k)
  delete!(m.int2str, k)
  delete!(m.str2int, c)
end


function initmodeldropdown(widget)
  
  # Establish a signal and initialize the conversion dictionaries
  sig = Signal("None")
  int2str = Dict{Int, String}()
  str2int = Dict{String, Int}()

  # Create the ModelDropdown and put the dafault "None" choice, make it active
  mdd = ModelDropdown(sig, widget, int2str, str2int)
  pushchoice!(mdd, "None")
  setproperty!(mdd.widget, :active, 0)

  # Register the callback
  id = signal_connect(mdd.widget, :changed) do w
    push!(mdd.signal, mdd.int2str[getproperty(w, :active, Int) + 1])
  end

  return mdd
end



# ---------------------------------------------------------------------------- #
# A DCellC model with additional name and description info

mutable struct NamedModel
  name :: String
  info :: String
  date :: DateTime
  model :: Model
end

function typestring(m :: NamedModel) 
  s = string(typeof(m.model))
  s = replace(s, "DCellC.", "")
  s = replace(s, "Image", "")
  return s
end

function initmodellist()
  return Signal(NamedModel[])
end

function Base.push!(ml::Signal{Vector{NamedModel}}, m::NamedModel)
  v = value(ml)
  push!(v, m)
  push!(ml, v) 
end

function Base.delete!(ml::Signal{Vector{NamedModel}}, idx)
  v = value(ml)
  delete!(v, idx)
  push!(ml, v)
end

function initmodellist(addmodellist, modeldropdown)
  modellist = Signal(NamedModel[])
  foreach(addmodellist) do list
    for file in list
      model, name, descr = modelload(file, name=true, description=true)
      date = Dates.unix2datetime(Base.Filesystem.ctime(file))
      m = NamedModel(name, descr, date, model)
      push!(modellist, m)
      pushchoice!(modeldropdown, name)
    end
    last = length(modeldropdown.int2str)
    setproperty!(modeldropdown.widget, :active, last - 1)
  end

  currentmodel = map(modeldropdown.signal, typ=Any) do dd
    if dd == "None"
      return nothing
    else
      ml = value(modellist)
      idx = find(x -> x.name == dd, ml)[1]
      return ml[idx]
    end
  end

  return modellist, currentmodel
end

function initmodelinfo(currentmodel, name, typ, date, text)
  foreach(currentmodel) do model
    if model != nothing
      push!(name, model.name)
      push!(typ, typestring(model))
      push!(date, Dates.format(model.date, "yyyy-mm-dd, HH:MM"))
      push!(text, model.info)
    else 
      push!(name, "--")
      push!(typ,  "--")
      push!(date, "--")
      push!(text, "")
    end
  end
end

function initapplymodel(currentmodel, currentdensity, currentframe, 
                        button, progress, history)
  foreach(button) do btn
    model, frame = value(currentmodel), value(currentframe)
    if model != nothing && frame != nothing
      dens = value(frame.density)
      cb(i, n) = setproperty!(progress.widget, :fraction, i / n)
      dens[:,:] = density_patched(model.model, frame.image, patchsize = 256, callback=cb)
      # TODO: for peakheights != 100, other upper bound is needed
      clamp!(dens, 0., 100.)
      push!(currentdensity, dens)
    end
  end
end
