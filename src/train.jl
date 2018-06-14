

struct TrainFrame
  id :: Int
  name :: String
  image :: Image
  label :: Label
  imagepath :: String
  labelpath :: String
  region :: NTuple{4, Int} # x y w h
end

function TrainFrame(id, name, image, label, imagepath, region)
  labelpath = joinpath(splitext(imagepath)[1], fileext(label))
  return TrainFrame(id, name, image, label, imagepath, labelpath, region)
end

function inittraining(build, trainmodelbutton, addmodellist, 
                      modellist, history, worker)

  # A dictionary of models and the corresponding constructors
  modeldict = Dict(
    "unetlike"    => UNetLike,
    "fcrna"       => FCRNA,
    "multiscale3" => Multiscale3
  )


  # The training window
  root = build["root"]
  trainwindow = build["trainingWindow"]
  trainlistbox = build["trainingListBox"]

  # Dropdowns
  modeldropdown = initmodeldropdown(build["trainingModelChoice"])
  modeltype = GtkReactive.dropdown([keys(modeldict)...], widget=build["trainingModelType"])
  optimizer = GtkReactive.dropdown(["adam", "rmsprop", "nesterov"], widget=build["trainingOptimizer"])

  # Checkboxes
  batchnorm    = GtkReactive.checkbox(true,  widget=build["trainingBatchNorm"])
  greyscale    = GtkReactive.checkbox(false, widget=build["trainingGreyscale"])
  embeddlabel  = GtkReactive.checkbox(true,  widget=build["trainingEmbeddLabel"])
  embeddimage  = GtkReactive.checkbox(false, widget=build["trainingEmbeddImage"])

  # Numeric parameters
  # TODO: I would like to use gtksignal=:changed here, but this segfaults when
  # the inputs become non-compatible to the type. Issue this at GtkReactive. or Gtk.jl!
  epochs    = textbox(10,  widget=build["trainingEpochs"]) 
  patchsize = textbox(256, widget=build["trainingPatchsize"])
  patchmode = textbox(5,   widget=build["trainingPatchmode"])
  batchsize = textbox(1,   widget=build["trainingBatchsize"])
  kernelsize   = textbox(7,    widget=build["trainingKernelsize"])
  kernelheight = textbox(100,  widget=build["trainingKernelheight"])
  learningrate = textbox(1e-3, widget=build["trainingLearningrate"])

  # Image operation
  imageop = textbox("Id()", widget=build["trainingImageOp"])

  # Buttons
  exportlesson  = GtkReactive.button("Export Lesson...",  widget=build["trainingExportLesson"])
  starttraining = GtkReactive.button("Train and save...", widget=build["trainingStart"])

  # Open the training window per click on the train button
  inittrainwindow(trainwindow, trainmodelbutton)

  # Exporting labels
  exportlessonfile = exportlessondialog(root, exportlesson)
  trainedmodelfile = trainedmodeldialog(root, starttraining)

  # Init trainframe and add the trainlistview
  trainlist = TrainFrame[]
  newtrainframe = inittrainlistview(root, trainlistbox, trainlist, history)

  # Model that is currently selected in training panel
  currentmodel = map(modeldropdown.signal, typ=Any) do dd
    if dd == "None"
      setproperty!(modeltype.widget, :sensitive, true)
      setproperty!(batchnorm.widget, :sensitive, true)
      setproperty!(greyscale.widget, :sensitive, true)
      return nothing
    else 
      setproperty!(modeltype.widget, :sensitive, false)
      setproperty!(batchnorm.widget, :sensitive, false)
      setproperty!(greyscale.widget, :sensitive, false)

      ml = value(modellist)
      return ml[dd]
    end
  end

  # React on changes of the modellist
  foreach(modellist) do list
    for (modelname, _) in list
      pushchoice!(modeldropdown, modelname) 
    end
  end

  function getlesson(embeddlabel, embeddimage)
    selections = getselections(value(trainlist), embeddlabel, embeddimage)
    cm = value(currentmodel)
    if cm != nothing
      model = cm.model
      it = imgtype(model)
      bn = hasbatchnorm(model) 
    else
      model = modeldict[value(modeltype)]
      it = value(greyscale) ? GreyscaleImage : RGBImage
      bn = value(batchnorm)
    end
    return Lesson(model,
                  imgtype = it,
                  batchnorm = bn,
                  folder    = "", # TODO
                  selections = selections,
                  optimizer = value(optimizer),
                  lr        = value(learningrate),
                  imageop   = parse(ImageOp, value(imageop)), # TODO
                  epochs    = value(epochs),
                  batchsize = value(batchsize),
                  patchsize = value(patchsize),
                  patchmode = value(patchmode),
                  kernelsize   = value(kernelsize),
                  kernelheight = value(kernelheight))
  end

  # React on exports of the lessonfile
  foreach(exportlessonfile) do file
    if file == ""
      return nothing
    end
    lesson = getlesson(value(embeddlabel), value(embeddimage))
    lessonsave(file, lesson)
  end

  foreach(trainedmodelfile) do file
    if file == ""
      return nothing
    end
    file = DCellC.joinext(file, ".dccm")
    lesson = getlesson(true, true)
    if !isempty(lesson.selections)
      w = value(worker)
      if !w.remote
        info("Start training on local worker")
        @async begin
          model = @fetchfrom localworker train(lesson)
          modelsave(file, model)
          push!(addmodellist, [file])
        end
      else
        @async begin
          info("Start training on remote worker")

          # Host information
          host = w.host
          #envsource = ""
          scriptdir = w.scriptdir

          if host == ""
            warn("No hostname given")
            return
          end
          #"/home/tstaudt/.julia/v0.6/DCellC/scripts"

          # Local and remote temporary file paths
          loclfile = DCellC.joinext(tempname(), ".dcct")
          remlfile = joinpath("/tmp", splitdir(loclfile)[2])

          locmfile = file
          remmfile = joinpath("/tmp", splitdir(locmfile)[2])

          # Save the lesson file and transfer it
          lessonsave(loclfile, lesson)
          cpcmd = `scp -C $loclfile $host:$remlfile`
          println(cpcmd)
          run(cpcmd)

          # Train using the lesson file
          trstr = "cd $scriptdir; ./dcellc.jl lesson $remlfile $remmfile"
          trcmd = `ssh -C $host "$trstr"`
          println(trcmd)
          run(trcmd)

          # Copy the resulting lesson file back
          cpcmd = `scp -C $host:$remmfile $locmfile`
          println(cpcmd)
          run(cpcmd)

          # Load the file to the active model list
          push!(addmodellist, [locmfile])
        end
      end
    else
      info("empty training set - do nothing")
    end
    return nothing
  end

  # Return the signal that is to be populated in the main window
  inittrainwindow(trainwindow, trainmodelbutton)
  return newtrainframe
end

# TODO: What to do if no labelpath is given?? -> use imagepath as default?
function getselections(trainlist, embeddlabel, embeddimage)
  selections = Selection[]
  for tf in trainlist
    lbl = embeddlabel ? tf.label : tf.labelpath
    img = embeddimage ? tf.image : tf.imagepath
    push!(selections, (img, lbl, tf.region))
  end
  return selections
end


function inittrainwindow(window, button)
  showall(window)
  foreach(button) do btn
    if btn
      visible(window, true)
    else
      visible(window, false)
    end
    return nothing
  end
end


function inittrainlistview(root, trainlistbox, trainlist, history)

  newtrainframe = Signal(Any, nothing)

  println("a1")
  store = GtkListStore(Int, String, Int, String)
  tmodel = GtkTreeModel(store)
  view  = GtkTreeView(tmodel)
  push!(trainlistbox, view)


  foreach(newtrainframe) do tf
    if tf != nothing
      # Add the train frame to the list of train frames
      push!(trainlist, tf)
      # Add the frame to the store
      x,y,w,h = tf.region
      reg = @sprintf "%d-%d x %d-%d" x (x+w-1) y (y+h-1)
      push!(store, (tf.id, tf.name, length(tf.label), reg))
      # Push some history
      push!(history, AddTrainFrame(tf.region))
    end
    return nothing
  end

  col1 = GtkTreeViewColumn("Id", 
                           GtkCellRendererText(), 
                           Dict([("text", 0)]))

  col2 = GtkTreeViewColumn("Image", 
                           GtkCellRendererText(), 
                           Dict([("text", 1)]))

  col3 = GtkTreeViewColumn("Spots", 
                           GtkCellRendererText(), 
                           Dict([("text", 2)]))

  col4 = GtkTreeViewColumn("Region", 
                           GtkCellRendererText(), 
                           Dict([("text", 3)]))

  push!(view, col1, col2, col3, col4)

  sel = GAccessor.selection(view)

  signal_connect(root, "key-press-event") do widget, event
    focused = getproperty(value(view), :has_focus, Bool)
    if focused && hasselection(sel) && event.keyval == 0x0000ffff # DELETE
      iter = selected(sel)

      # TODO: Fix Gtk.jl bug for index_from_iter for both models and stores!!
      index = parse(Int, Gtk.get_string_from_iter(GtkTreeModel(store), iter)) + 1
      region = trainlist[index].region
      push!(history, RemoveTrainFrame(region))

      deleteat!(trainlist, index)
      deleteat!(store, iter)
    end
  end
  
  return newtrainframe
end


function inittrainselection(newtrainframe, canvas, current, currentframe, currentzr)
 
  xy = XY{UserUnit}(-1, -1)
  rb = GtkReactive.RubberBand(xy, xy, false, 10)
  local ctxcopy

  filter(b) = (b.modifiers & SHIFT) != 0
  initrubber(b) = filter(b) && b.button == 1

  active = Signal(false)

  # Initialize rubber banding
  foreach(canvas.mouse.buttonpress) do btn
    if initrubber(btn) && value(frame) != nothing
      push!(active, true)
      ctxcopy = copy(Graphics.getgc(canvas))
      rb.pos1 = rb.pos2 = btn.position
    end
    return nothing
  end

  # Dragging phase
  foreach(canvas.mouse.motion) do btn
    if value(active) == true
      btn.button == 0 && return nothing # some button must be pressed
      GtkReactive.rubberband_move(canvas, rb, btn, ctxcopy)
    end
  end

  function stop_callback(canvas, bb)
    zr = value(currentzr)
    id = value(current)
    frame = value(currentframe)
    x1, y1 = imgcoords(bb.xmin, bb.ymin, canvas.widget, zr)
    x2, y2 = imgcoords(bb.xmax, bb.ymax, canvas.widget, zr)
    region = (x1, y1, x2 - x1, y2 - y1)
    label = crop(frame.label, region...)
    image = crop(frame.image, region...)
    tf = TrainFrame(id, frame.name, image, label, frame.path, region)
    push!(newtrainframe, tf)
    info("Sucessfully added new train frame")
  end

  # Finish the rubber banding
  foreach(canvas.mouse.buttonrelease) do btn
    if value(active) == true
      btn.button == 0 && return nothing # some button must be pressed ... why?
      push!(active, false)
      GtkReactive.rubberband_stop(canvas, rb, btn, ctxcopy, stop_callback)
    end
  end
end

# TODO: Bug in GTKReactive.jl!! File it!
function GtkReactive.rb_erase(r::Cairo.GraphicsContext, rb::GtkReactive.RubberBand, ctxcopy)
  GtkReactive.rb_set(r, rb)
  Cairo.save(r)
  Cairo.reset_transform(r)
  Cairo.save(ctxcopy)
  Cairo.reset_transform(ctxcopy)
  Cairo.set_source(r, ctxcopy)
  Cairo.set_line_width(r, 3)
  Cairo.set_dash(r, Float64[])
  Cairo.set_operator(r, Cairo.OPERATOR_SOURCE) # This is the needed line
  Cairo.stroke(r)
  Cairo.restore(r)
  Cairo.restore(ctxcopy)
end

