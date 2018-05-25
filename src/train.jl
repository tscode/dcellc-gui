

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

function inittraining(build, trainmodelbutton)

  # The training window
  root = build["root"]
  trainwindow = build["trainingWindow"]
  trainlistbox = build["trainingListBox"]

  # Dropdowns
  modeldropdown = initmodeldropdown(build["trainingModelChoice"])
  modeltype = GtkReactive.dropdown(["multiscale3", "fcrna", "unetlike"], widget=build["trainingModelType"])
  optimizer = GtkReactive.dropdown(["adam", "rmsprop", "nesterov"], widget=build["trainingOptimizer"])

  # Checkboxes
  batchnorm   = GtkReactive.checkbox(true, widget=build["trainingBatchNormalization"])
  greyscale   = GtkReactive.checkbox(false, widget=build["trainingGreyscale"])
  embeddlabel = GtkReactive.checkbox(true, widget=build["trainingEmbeddLabel"])
  embeddimage = GtkReactive.checkbox(false, widget=build["trainingEmbeddImage"])

  # Numeric parameters
  epochs    = GtkReactive.textbox(10, widget=build["trainingEpochs"])
  patchsize = GtkReactive.textbox(256, widget=build["trainingPatchsize"])
  patchmode = GtkReactive.textbox(5, widget=build["trainingPatchmode"])
  batchsize = GtkReactive.textbox(1, widget=build["trainingBatchsize"])
  kernelsize   = GtkReactive.textbox(7, widget=build["trainingKernelsize"])
  kernelheight = GtkReactive.textbox(100, widget=build["trainingKernelheight"])
  learningrate = GtkReactive.textbox(1e-3, widget=build["trainingLearningrate"])

  # Buttons
  exportlesson  = GtkReactive.button("Export Lesson...", widget=build["trainingExportLesson"])
  starttraining = GtkReactive.button("Start Training", widget=build["trainingStart"])

  # Open the training window per click on the train button
  inittrainwindow(trainwindow, trainmodelbutton)


  # Exporting labels
  exportlessonfile = exportlessondialog(root, exportlesson)

  # Init trainframe and add the trainlistview
  trainlist = TrainFrame[]
  newtrainframe = inittrainlistview(root, trainlistbox, trainlist)

  # React on exports of the lessonfile
  foreach(exportlessonfile) do file
    selections = getselections(value.((trainlist, embeddlabel, embeddimage))...)
    lesson = Lesson(FCRNA,
                    folder    = "", # TODO
                    selections = selections,
                    imgtype   = value(greyscale) ? GreyscaleImage : RGBImage,
                    batchnorm = value(batchnorm),
                    optimizer = value(optimizer),
                    lr        = value(learningrate),
                    imageop   = Id(), # TODO
                    epochs    = value(epochs),
                    batchsize = value(batchsize),
                    patchsize = value(patchsize),
                    patchmode = value(patchmode),
                    kernelsize   = value(kernelsize),
                    kernelheight = value(kernelheight))

    lessonsave(file, lesson)
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


function inittrainlistview(root, trainlistbox, trainlist)

  newtrainframe = Signal(Any, nothing)

  println("a1")
  store = GtkListStore(Int, String, Int, String)
  view  = GtkTreeView(GtkTreeModel(store))
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
      #push!(history, AddTrainFrame())
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

  #signal_connect(root, "key-press-event") do widget, event
  #  if hasselection(sel) && event.keyval == 0x0000ffff # DELETE
  #    iter = selected(sel)
  #    deleteat!(trainlist, index_from_iter(store, iter))
  #    deleteat!(store, iter)
  #  end
  #end
  
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
    @show initrubber(btn)
    @show (btn.modifiers & SHIFT) != 0
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
    @show region
    tf = TrainFrame(id, frame.name, frame.image, frame.label, frame.path, region)
    push!(newtrainframe, tf)
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