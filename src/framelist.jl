
# ---------------------------------------------------------------------------- #
# Initialize the side-panel; overview over all loaded images

# When the add-frame dialog is called, add the newly selected images to the
# store (used for display in sidebar) and to the framelist (used for model 
# application ect...)
function initframelistview(root, list, box, history, config)

  # Create the list store
  store = GtkListStore(String, Int)

  # Create the list view and attach it to the corresponding box
  view  = GtkTreeView(GtkTreeModel(store)) 
  push!(box, view)

  # Create signals
  current = Signal(-1)
  framelist = Signal(Dict{Int,Any}())

  # Update the framelist and the viewstore each time new images are selected
  foreach(list) do filelist
    fl = value(framelist)
    index = isempty(fl) ? 1 : maximum(keys(fl)) + 1
    @async begin
      for file in filelist
        frame = Frame(file)
        #push!(store, (thumbpixbuf(frame), frame.name, index))
        push!(store, (frame.name, index))
        fl[index] = frame
        push!(framelist, fl)
        index += 1
      end
      push!(history, AddImages(filelist))
    end
  end

  # The column view objects needed for each column that is to be displayed
  #col1 = GtkTreeViewColumn("Pixbuf", 
  #                          GtkCellRendererPixbuf(),
  #                          Dict([("pixbuf", 0)]))
  col1 = GtkTreeViewColumn("Id", 
                           GtkCellRendererText(), 
                           Dict([("text", 1)]))

  col2 = GtkTreeViewColumn("Image", 
                           GtkCellRendererText(), 
                           Dict([("text", 0)]))

  # TODO: Currently no preview pics!
  push!(view, col1, col2)

  currentframe = map(current, framelist, typ=Any) do index, list
    return index > 0 ? list[index] : nothing
  end

  # What follows is an outrageous hack, due to segfaults I receive
  # when trying to delete rows of the selection store while having
  # a signal connected to the GtkTreeSelection.
  # This probably is a Bug in Gtk.jl
  # TODO: Issue this bug!

  sel = GAccessor.selection(view)

  function sel_function(sel) 
    if hasselection(sel)
      index = store[selected(sel), 2]
      push!(current, index)
    else
      push!(current, -1)
    end
  end

  handler = signal_connect(sel_function, sel, "changed")

  # The hack begins...
  signal_connect(root, "key-press-event") do widget, event
    focused = getproperty(value(view), :has_focus, Bool)
    if focused && hasselection(sel) && event.keyval == 0x0000ffff # DELETE
      # Get the index
      index = value(current)
      # Disconnect the signal
      signal_handler_disconnect(sel, handler)
      # Delete the row
      deleteat!(store, selected(sel))
      # Show the new selection
      sel_function(sel)
      # Reconnect the signal
      handler = signal_connect(sel_function, sel, "changed")

      # Remove the frame
      fl = value(framelist)
      push!(history, RemoveImages([value(currentframe).name]))
      delete!(fl, index)
      push!(framelist, fl)
    end
  end

  # Return the two signals
  return current, framelist, currentframe
end


function thumbpixbuf(frame :: Frame)
  thumb = frame.thumb
  data = Array{Gtk.RGB}(size(thumb)...)
  for i in size(thumb, 2), j in size(thumb, 1)
    c = thumb[j,i]
    c = round.(UInt8, 255 .* (c.r, c.g, c.b))
    data[j,i] = Gtk.RGB(c...)
  end
  return GdkPixbuf(data = data, has_alpha=false)
end

function initlabelsavebutton(button, framelist, history)
  foreach(button) do btn
    frames = value(framelist)
    for (_, frame) in frames
      if length(frame.label) != 0
        lblsave(splitext(frame.path)[1], frame.label)
      end
    end
    if !isempty(frames)
      push!(history, SaveLabels())
    end
  end
end

