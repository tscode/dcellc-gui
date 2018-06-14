#! /usr/bin/env julia

# Create a worker thread that conducts some operations in the background
# ---------------------------------------------------------------------------- #

dir = splitdir(Base.source_path())[1]
info("DCellC started in directory '$dir'")

const localworker = addprocs(1, enable_threaded_blas=true)[1]

# ---------------------------------------------------------------------------- #
# Load and import packages

@everywhere using Knet
@everywhere using DCellC

@everywhere using Gtk
@everywhere using GtkReactive
@everywhere using IntervalSets

@everywhere import Reactive
@everywhere import Images
@everywhere import ImageTransformations
@everywhere import Graphics
@everywhere import Cairo

# ---------------------------------------------------------------------------- #
# Load and import scripts

include("general.jl")
include("history.jl")
include("dialog.jl")
include("config.jl")
include("frame.jl")
include("framelist.jl")
include("model.jl")
include("train.jl")

# Also load the file "frame.jl" on the remote worker
# TODO: loading frames in concurrent thread does not work!
#@fetchfrom localworker include(joinpath(dir, "general.jl"))
#@fetchfrom localworker include(joinpath(dir, "history.jl"))
#@fetchfrom localworker include(joinpath(dir, "dialog.jl"))
#@fetchfrom localworker include(joinpath(dir, "config.jl"))
#@fetchfrom localworker include(joinpath(dir, "frame.jl"))
#@fetchfrom localworker include(joinpath(dir, "framelist.jl"))
#@fetchfrom localworker include(joinpath(dir, "model.jl"))
#@fetchfrom localworker include(joinpath(dir, "train.jl"))


# ---------------------------------------------------------------------------- #
# Main function

function main(buildfile = "$dir/../glade/dcellc.glade")

  # Load the glade file
  build = GtkBuilder(filename = buildfile)

  # Extract Gtk widgets
  root          = build["root"]
  mainframeview = build["mainFrameView"]
  framelistbox  = build["frameListBox"]

  # Reactive Gtk widgets

  # Adding frames, saving labels, showing the previous action
  addframesbutton = GtkReactive.button(widget=build["addFramesButton"])
  savelabelbutton = GtkReactive.button(widget=build["saveLabelButton"])
  lastaction      = GtkReactive.label("", widget=build["lastAction"])

  # Frame information 
  frameinfoname   = GtkReactive.label("--", widget=build["frameInfoName"])
  frameinfotype   = GtkReactive.label("--", widget=build["frameInfoType"])
  frameinfores    = GtkReactive.label("--", widget=build["frameInfoRes"])
  frameinfotext   = GtkReactive.textarea("", widget=build["frameInfoText"])

  # Model information 
  modelinfoname   = GtkReactive.label("--", widget=build["modelInfoName"])
  modelinfotype   = GtkReactive.label("--", widget=build["modelInfoType"])
  modelinfodate   = GtkReactive.label("--", widget=build["modelInfoDate"])
  modelinfotext   = GtkReactive.textarea("", widget=build["modelInfoText"])

  # Settings/options for counting
  thresholdslider = GtkReactive.slider(1:100, value = 30, 
                                       widget=build["thresholdSlider"])

  mergedistslider = GtkReactive.slider(0:30, value = 5, 
                                       widget=build["mergedistSlider"])

  # Managing models
  modeldropdown     = initmodeldropdown(build["modelSelection"])
  loadmodelsbutton  = GtkReactive.button(widget=build["loadModelsButton"])
  trainmodelbutton  = GtkReactive.togglebutton(false, 
                                               widget=build["trainModelButton"])

  # Applying models and counting
  applymodelbutton  = GtkReactive.button(widget=build["applyModelButton"])
  acceptlabelbutton = GtkReactive.button(widget=build["acceptLabelButton"])

  showdensity       = GtkReactive.togglebutton(false, 
                                               widget=build["densityToggleButton"])

  showlabel         = GtkReactive.togglebutton(true, 
                                               widget=build["labelToggleButton"])

  countingmanual  = GtkReactive.label("0", widget=build["countingManual"])
  countingauto    = GtkReactive.label("0", widget=build["countingAuto"])
  countingtotal   = GtkReactive.label("0", widget=build["countingTotal"])

  # Show cursor position
  currentcursorx  = GtkReactive.label("", widget=build["currentCursorX"])
  currentcursory  = GtkReactive.label("", widget=build["currentCursorY"])
  currentzoom     = GtkReactive.label("", widget=build["currentZoom"])

  # The central progress bar
  # TODO: Bug in GtkReactive for progressbar creation, missing ';'
  mainprogressbar = GtkReactive.progressbar(ClosedInterval(0:100), 
                                            widget = build["mainProgressBar"])

  # Initialize history 
  history = inithistory()

  config, worker = initmainmenu(build)

  # Register add-frame dialog
  addframelist = addframedialog(root, addframesbutton)

  # Register add-model dialog
  addmodellist = addmodeldialog(root, loadmodelsbutton)

  # The list of loaded models
  modellist, currentmodel = initmodellist(addmodellist, modeldropdown)


  initmodelinfo(currentmodel,
                modelinfoname,
                modelinfotype,
                modelinfodate,
                modelinfotext)

  # Main panel -- selection zone
  # Signals
  current, framelist, currentframe = initframelistview(root,
                                                       addframelist, 
				                                               framelistbox, 
                                                       history)

  initgeneralinfo(currentframe,
                  frameinfoname,
                  frameinfotype,
                  frameinfores,
                  frameinfotext)

  initlabelsavebutton(savelabelbutton, framelist, history)

  # Main panel -- work zone
  currentzr            = inithelpersignals(current, framelist)
  imgcanvas, lblcanvas = initcanvases(mainframeview)

  # Stick threshold-level and merge distance to the respective buttons
  threshold, mergedist = signal(thresholdslider), signal(mergedistslider)

  # Current manual label and current density
  currentlbl, currentdens = initcounting(currentframe, threshold, mergedist)

  # Show the last action in a label-widget, bottom left
  initlastaction(lastaction, history)

  # Enable panning and zooming by scrolling
  initpanzoom(lblcanvas, currentzr, currentframe)

  # Print zooming information, bottom right
  initzoominfo(currentzoom, currentframe, currentzr)

  # Print mouse position information, bottom right
  initmouseposition(currentcursorx, currentcursory, 
                    lblcanvas, currentframe, currentzr)

  # Adding and removing of label spots via mouse clicks,
  # drawing the canvases
  runcanvases(imgcanvas, lblcanvas, currentlbl, currentdens,
              currentframe, currentzr, config, history, 
              signal(showdensity), signal(showlabel))

  # Show information about the current label / autolabel
  initcountinfo(countingmanual, countingauto, countingtotal,
                currentdens, currentlbl, currentframe, threshold, mergedist)

  # Prepare the button that applies the current model on the current frame
  # and updates the density
  # Also initializes the accept button
  initmodel(current, currentmodel, currentdens, currentlbl, 
            currentframe, applymodelbutton, acceptlabelbutton, 
            mergedist, mainprogressbar, history, worker)


  # Training window
  newtrainframe = inittraining(build, trainmodelbutton, 
                               addmodellist, modellist, history, worker)


  inittrainselection(newtrainframe, lblcanvas,
                     current, currentframe, currentzr)

  # Display the root window
  showall(root)

  # All preparations done -- wait until the window is closed

  c = Condition()
  signal_connect(root, :destroy) do w
    notify(c)
  end
  wait(c)
end

main()
