
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
  if !haskey(m.str2int, c)
    push!(m.widget, c)
    k = length(m.str2int) + 1
    m.str2int[c] = k
    m.int2str[k] = c
  end
  return nothing
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

function Base.push!(ml::Signal{Dict{String, NamedModel}}, m::NamedModel)
  v = value(ml)
  v[m.name] = m
  push!(ml, v) 
end

function Base.delete!(ml::Signal{Dict{String, NamedModel}}, name::String)
  v = value(ml)
  delete!(v, name)
  push!(ml, v)
end

function initmodellist(addmodellist, modeldropdown)
  modellist = Signal(Dict{String, NamedModel}())
  foreach(addmodellist) do list
    for file in list
      model, name, descr = modelload(file, name=true, description=true)
      date = Dates.unix2datetime(Base.Filesystem.ctime(file))
      m = NamedModel(name, descr, date, model)
      push!(modellist, m) # this can overwrite previous models!
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
      return ml[dd]
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

#function mergelabel(manual, auto, dist)
#  data = copy(auto.data)
#  for cm in manual
#    filter!(data) do ca
#      norm([(cm .- ca)...]) > dist
#    end
#  end
#  return Label([manual.data; data])
#end

function initcountinfo(countingmanual, countingauto, countingtotal, 
                       currentdens, currentlbl, currentframe, threshold, mergedist)

  foreach(currentdens, currentlbl, 
          currentframe, threshold, mergedist) do dens, lbl, frame, thr, dist
    # TODO: Mergedist
    if frame != nothing
      total = DCellC.merge(lbl, frame.autolabel, dist)
      merged = length(lbl) + length(frame.autolabel) - length(total)
      push!(countingmanual, "$(length(lbl))")
      push!(countingauto, "$(length(frame.autolabel))")
      push!(countingtotal, "$(length(total))\t($merged merged)")
    else
      push!(countingmanual, "--")
      push!(countingauto, "--")
      push!(countingtotal, "--")
    end
  end
end


function initmodel(current, currentmodel, currentdensity, 
                   currentlbl, currentframe, applybutton, 
                   acceptbutton, mergedist, progress, history, worker)

  # Applying the model
  foreach(applybutton) do btn
    model, frame = value(currentmodel), value(currentframe)

    if model == nothing && frame != nothing

      info("Resetting density")

      # Update the density and its signal
      frame.density[:,:] = 0.
      push!(currentdensity, frame.density)

      # History update: Density resetted
      push!(history, ResetDensity())

    elseif frame != nothing
      dens = frame.density
      image = imgtype(model.model) == RGBImage ? frame.image : greyscale(frame.image)
      m = model.model

      # Need an remote channel through which the working process can send status information
      const rc = RemoteChannel(() -> Channel{Tuple{Int, Int}}(10), 1)

      # Variable to check if the worker is still running
      running = true

      w = value(worker)
      index = value(current)
      
      if !w.remote # not remote

        info("Begin local density calculation")

        # One thread that lets the worker calculate the density
        @async begin

          at = gpu() >= 0 ? KnetArray{Float32} : Array{Float32}
          
          # History update: Computation started
          push!(history, ApplyModelStart())

          # Calculation on the worker
          dens[:,:] = @fetchfrom localworker begin
            cb(i, n) = put!(rc, (i, n))
            # TODO: make the patchsize an option!
            d = density_patched(m, image, patchsize = 512, callback = cb, at = at)
            # rescale density to region from 0 to 100
            clamp.(d / max(maximum(d), 10), 0, 1.) * 100
          end

          # Update the density signal
          if index == value(current)
            push!(currentdensity, dens)
          end

          # History update: Computation finished
          push!(history, ApplyModelEnd())
          
          # Indicate that the computation is finished
          running = false
        end

        # Second thread to update the progress bar
        @async begin
          i, n = 0, 1
          while i != n
            i, n = take!(rc)
            push!(progress, round(Int, i/n*100))
          end
          push!(progress, 0)
        end

      else # remote
        info("Begin remote density calculation")

        @async begin
          # Host information
          host = w.host
          scriptdir = w.scriptdir

          if host == ""
            warn("No hostname given")
            return
          end

          # Local and remote temporary file paths
          base = tempname()
          locmfile = DCellC.joinext(base, ".dccm")
          remmfile = joinpath("/tmp", splitdir(locmfile)[2])

          locifile = DCellC.joinext(base, ".tif")
          remifile = joinpath("/tmp", splitdir(locifile)[2])

          locdfile = DCellC.joinext(base*"-dens", ".tif")
          remdfile = joinpath("/tmp", splitdir(locdfile)[2])

          # Save the image and model, and transfer them
          imgsave(locifile, image)
          modelsave(locmfile, m)

          cpmcmd = `scp -C $locmfile $host:$remmfile`
          cpicmd = `scp -C $locifile $host:$remifile`
          println(cpmcmd)
          run(cpmcmd)
          println(cpicmd)
          run(cpicmd)

          # Apply the model and create the density file
          apstr = "cd $scriptdir; ./dcellc.jl apply --density $remmfile $remifile"
          apcmd = `ssh -C $host "$apstr"`
          println(apcmd)
          run(apcmd)

          # Copy the density back and load it
          cpdcmd = `scp -C $host:$remdfile $locdfile`
          println(cpdcmd)
          run(cpdcmd)

          dens[:,:] = imgload(locdfile).data * 100

          # Update the density signal
          if index == value(current)
            push!(currentdensity, dens)
          end

          # History update: Computation finished
          push!(history, ApplyModelEnd())
        end
      end
    end
    return nothing
  end

  # Accepting the model output
  foreach(acceptbutton) do btn
    frame = value(currentframe)
    if frame != nothing
      lbl = value(currentlbl)
      dist = value(mergedist)
      frame.label = DCellC.merge(lbl, frame.autolabel, dist)
      push!(currentlbl, frame.label)
      frame.density[:,:] = 0.
      push!(currentdensity, frame.density) 
    end
  end
end
