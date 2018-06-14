
# ---------------------------------------------------------------------------- #
# Structs that hold all necessary information about one image frame

mutable struct Frame
  name :: String             # basename
  path :: String             # file path to the image file
  image :: Image             # DCellC image data
  label :: Label             # accepted DCellC label
  autolabel :: Label         # automatically generated DCellC label
  density :: Matrix{Float32} # Density map
  source :: Array            # Images.jl image data
  buffer :: Array            # Images.jl image data
  comment :: String
  thumb :: Array             # Images.jl image data of a small preview
  gamma :: Real              # Gamma value for displaying images
  vmin :: Real               # Minimal value that is to be displayed
  vmax :: Real               # Maximal value that is to be displayed
  chist :: Array             # Cumulative histogram of the intensities
  zr :: ZoomRegion           # Zoom region
end

function Frame(path :: String)
  # Get the basename
  name = basename(path)

  # Load the image as Images.jl image
  source = Images.load(path)

  # Create a copy of the source image 
  buffer = copy(Images.channelview(source))
	
  # Convert this image to an DCellC image used for model training
  # TODO: Note that this rescales the image -- not sure if this is
  # problematic or not. Test!
  image = imgconvert(source)

  # Try to load the label corresponding to the image file
  # If it does not work, return an empty label
  label = try lblload(splitext(path)[1]) catch Label() end
  autolabel = Label()

  # Initialize an empty density map
  # This value gets updated if a model is applied to the current frame
  density = zeros(Float32, imgsize(image))

  # Some comment texts
  comment = ""

  # Create a thumbnail image with resolution of at most 200x200 px
  factor = maximum(imgsize(image)) / 100
  res = floor.(Int, imgsize(image) ./ factor)
  thumb = ImageTransformations.imresize(source, res)

  # Some information about how the image is to be displayed
  gamma = 1.
  vmin = minimum(Images.channelview(source))
  vmax = maximum(Images.channelview(source))

  # Set the buffer such that vmin, vmax, and gamma are respected
  frameadapt(buffer, source, vmin, vmax, gamma)

  # Also store an intensity histogram in order to calculate vmin/vmax fast
  chist = cumulativehist(source)

  # Instantiate the zoom region for the current image
  zr = ZoomRegion(source)

  # Return the frame object 
  return Frame(name, path, image, label, autolabel, density, source, 
               buffer, comment, thumb, gamma, vmin, vmax, chist, zr)
end

# ---------------------------------------------------------------------------- #
# Helper functions to adapt and display the source image

function vminmax(chist, pmin, pmax)
  imin = round(Int, length(chist)*vmin/100) + 1
  imax = round(Int, length(chist)*vmax/100) 
  return chist[imin], chist[imax]
end

function frameadapt(buffer, source, vmin, vmax, gamma)
  cview = Images.channelview(Images.adjust_gamma(source, gamma))
  buffer[:,:,:] = (clamp.(cview, vmin, vmax) - vmin) / (vmax - vmin)
end


# ---------------------------------------------------------------------------- #
# Create the two layers of canvases needed for 
# displaying the image and labels

function initcanvases(frameview)
  imgcanvas = canvas(UserUnit)
  lblcanvas = canvas(UserUnit)
  push!(frameview, imgcanvas)
  push!(frameview, lblcanvas)
  return imgcanvas, lblcanvas
end

# ---------------------------------------------------------------------------- #
# Initialize signals for the current zoomregion

function inithelpersignals(current, framelist)
  zr = map(current, framelist) do index, list
    return index > 0 ? list[index].zr : fallbackzoomregion()
  end
  return zr
end

# ---------------------------------------------------------------------------- #
# Activate panning and zooming by adapting the 
# current zoomregion

function initpanzoom(canvas, currentzr, frame)

  filter(b) = (b.modifiers & CONTROL) != 0
  initpan(b) = filter(b) && b.button == 1 && b.clicktype == BUTTON_PRESS
  
  # Zoom to the current mouse position when scrolling
  foreach(canvas.mouse.scroll) do bb
    if filter(bb) && value(frame) != nothing
      s = bb.direction == UP ? 1/1.2 : 1.2  # zoom factor per scroll step
      zr = value(currentzr)
      # This conversion is necessary to make the GtkReactive.zoom function work
      imgpos = XY(UserUnit.(imgcoords(bb, canvas.widget, zr))...)
      newzr = zoom(zr, s, imgpos)
      push!(currentzr, newzr)
      # Also update the zr value hold by the current frame
      value(frame).zr = newzr
      return nothing
    end
  end

  # Pan the image
  active = Reactive.Signal(false)
  dummybtn = MouseButton{UserUnit}()
  local pos1, zr1, mat

  # Initialize panning when a button is pressed
  foreach(canvas.mouse.buttonpress) do btn
    if initpan(btn) && value(frame) != nothing
      push!(active, true)
      # Convert to absolute position
      pos1 = XY(GtkReactive.convertunits(DeviceUnit, canvas, btn.position.x, btn.position.y)...)
      zr1 = value(currentzr).currentview
      m = Cairo.get_matrix(Graphics.getgc(canvas))
      mat = inv([m.xx m.xy 0; m.yx m.yy 0; m.x0 m.y0 1])
      return nothing
    end
  end

  # Drag the zoomregion if the mouse is moved 
  foreach(filterwhen(active, dummybtn, canvas.mouse.motion)) do btn
    if btn.button != 0 && value(frame) != nothing
      xd, yd = GtkReactive.convertunits(DeviceUnit, canvas, btn.position.x, btn.position.y)
      dx, dy, _ = mat * [xd-pos1.x, yd-pos1.y, 1]
      fv = value(currentzr).fullview
      cv = XY(GtkReactive.interior(minimum(zr1.x)-dx..maximum(zr1.x)-dx, fv.x),
              GtkReactive.interior(minimum(zr1.y)-dy..maximum(zr1.y)-dy, fv.y))

      if cv != value(currentzr).currentview
        newzr = ZoomRegion(fv, cv)
        push!(currentzr, newzr)
        value(frame).zr = newzr
      end
      return nothing
    end
  end

  # Finish the panning movement
  foreach(filterwhen(active, dummybtn, canvas.mouse.buttonrelease)) do btn
    if btn.button != 0
      push!(active, false)
    end
  end
  preserve(active)
end

# ---------------------------------------------------------------------------- #
# Calculate image coordinates for mouse events

function imgcoords(x, y, canvas, zr)
  cv = zr.currentview
  mins = (cv.x.left, cv.y.left)
  maxs = (cv.x.right, cv.y.right)
  s = size(canvas)
  p = (x, y)
  imgx, imgy = mins .+ (p ./ s) .* (maxs .- mins)
  return round.(Int, (imgx, imgy))
end

imgcoords(btn, can, zr) = imgcoords(btn.position.x, btn.position.y, can, zr)


# ---------------------------------------------------------------------------- #
# Convert image coordinates to canvas coordinates

function canvascoords(imgcoord, canvas, zr)
  s = size(canvas)
  cv = zr.currentview
  width  = cv.x.right - cv.x.left
  height = cv.y.right - cv.y.left

  imgx, imgy = imgcoord
  x = (imgx - cv.x.left) / width
  y = (imgy - cv.y.left) / height
  return round.(Int, (x, y) .* s)
end

# ---------------------------------------------------------------------------- #
# Fallback zoom region for the `currentzr` signal

function fallbackzoomregion()
  return GtkReactive.ZoomRegion(zeros(10, 10))
end

# ---------------------------------------------------------------------------- #
# Filter the label for spots in the zoomregion

function zoomregionlabel(label::Label, zr)
  cv = zr.currentview
  return Label([(x,y) for (x,y) in label if (x in cv.x && y in cv.y)])
end

# ---------------------------------------------------------------------------- #
# Get the index of the spot in `lbl` that is nearest to

function nearestspotidx(lbl::Label, imgcoord::Tuple{Int,Int})
  if length(lbl) > 0
    return indmin(norm(imgcoord .- [x,y]) for (x,y) in lbl)
  else
    return nothing
  end
end

# ---------------------------------------------------------------------------- #
# Write zoom info in the footer

function initzoominfo(zoom, currentframe, currentzr)
  foreach(currentframe, currentzr) do frame, zr
    if frame != nothing
      fv, cv = zr.fullview, zr.currentview
      z = (fv.x.right - fv.x.left) / (cv.x.right - cv.x.left) * 100
      push!(zoom, @sprintf("%d%%", round(Int, z)))
    else
      push!(zoom, "")
    end
  end
end

# ---------------------------------------------------------------------------- #
# Write mouse position in the footer

function initmouseposition(cursorx, cursory, canvas, currentframe, currentzr)
  foreach(currentframe, currentzr, canvas.mouse.motion) do frame, zr, btn
    if frame != nothing
      imgx, imgy = imgcoords(btn, canvas.widget, zr)
      push!(cursorx, @sprintf("x = %d", imgx))
      push!(cursory, @sprintf("y = %d", imgy))
    else
      push!(cursorx, "")
      push!(cursory, "")
    end
  end
end

# ---------------------------------------------------------------------------- #
# Draw image and label canvases

function runcanvases(imgcanvas, lblcanvas, currentlbl, 
                     currentdens, currentframe, currentzr, 
                     spotconfig, history, showdens, showlabel)

  # Mouse signals
  motion  = lblcanvas.mouse.motion
  press   = lblcanvas.mouse.buttonpress
  release = lblcanvas.mouse.buttonrelease

  # Copy data from the image source to the canvas
  preserve(draw(imgcanvas, currentframe, currentzr, showdens) do can, frame, zr, dens
    if frame != nothing
      cv = zr.currentview
      # show either the source image or the density map
      if dens
        buffer = Images.colorview(Images.Gray, frame.density) / 100
      else
        buffer = Images.colorview(Images.RGB, frame.buffer)
      end
      imageview = view(buffer, UnitRange{Int}(cv.y), UnitRange{Int}(cv.x))
      copy!(can, imageview)
      set_coordinates(can, zr)
    else
      ctx = Graphics.getgc(can)

      # Make sure the surface is clean
      Graphics.save(ctx)
      Cairo.set_operator(ctx, Cairo.OPERATOR_CLEAR)
      Graphics.paint(ctx)
      Graphics.restore(ctx)
    end
  end)

  # Signal that contains the index of the nearest label spot
  nearest = Signal(-1)
  foreach(currentframe, 
          currentlbl, 
          motion, 
          currentzr) do frame, lbl, btn, zr

    if frame != nothing
      imgx, imgy = imgcoords(btn, lblcanvas.widget, zr)
      n = nearestspotidx(lbl, (imgx, imgy))
      if n != nothing && n != value(nearest)
        push!(nearest, n)
      end
    end
  end

  filter(btn) = (btn.modifiers & CONTROL) == (btn.modifiers & SHIFT) == 0

  # Add and remove labels
  foreach(release) do btn
    lbl = value(currentlbl)
    if lbl != nothing
      zr = value(currentzr)
      imgx, imgy = imgcoords(btn, lblcanvas.widget, zr)

      # Left mouse click - add new label
      if (btn.button == 1 && filter(btn))
        push!(lbl, (imgx, imgy))
        push!(currentlbl, lbl)
        push!(nearest, length(lbl))
        push!(history, AddSpot((imgx, imgy)))

      # Middle mouse click - remove nearest label
      elseif (btn.button == 2 && filter(btn))
        n = value(nearest)
        if n != -1 && n <= length(lbl)
          x, y = lbl[n]
          deleteat!(lbl, n)
          nnew = nearestspotidx(lbl, (imgx, imgy))
          push!(currentlbl, lbl)
          push!(nearest, nnew == nothing ? -1 : nnew)
          push!(history, RemoveSpot((imgx, imgy)))
        end

      # Right mouse click - re-place nearest label
      elseif (btn.button == 3 && filter(btn))
        n = value(nearest)
        if n != -1 && n <= length(lbl)
          x, y = lbl[n]
          lbl[n] = (imgx, imgy)
          push!(currentlbl, lbl)
          push!(history, MoveSpot((x,y), (imgx, imgy)))
        end

      end 
    end
  end

  # Draw the label
  preserve(draw(lblcanvas, 
                currentframe, 
                currentlbl,
                currentdens,
                currentzr, 
                nearest, 
                spotconfig,
                showlabel) do can, frame, lbl, dens, zr, ns, config, sl

    # Draw labels if there is an active frame and if labels should be drawn
    if frame != nothing && sl

      cv  = zr.currentview
      ctx = Graphics.getgc(can)
      s   = size(can)

      # Clear the surface
      Graphics.save(ctx)
      Cairo.set_operator(ctx, Cairo.OPERATOR_CLEAR)
      Graphics.paint(ctx)
      Graphics.restore(ctx)

      # Draw labels
      Graphics.set_source_rgb(ctx, config.spotcolor...)
      lbl = zoomregionlabel(lbl, zr)

      for coords in lbl
        x, y = canvascoords(coords, can, zr)
        Graphics.arc(ctx, x, y, config.spotradius, 0, 2pi)
        Graphics.stroke(ctx)
      end

      # Draw autolabels
      Graphics.set_source_rgb(ctx, config.autospotcolor...)
      albl = zoomregionlabel(frame.autolabel, zr)

      for coords in albl
        x, y = canvascoords(coords, can, zr)
        Graphics.arc(ctx, x, y, config.spotradius, 0, 2pi)
        Graphics.stroke(ctx)
      end

      # Draw the label that the mouse is nearest especially colored
      # And remove it by right-clicking
      btn = value(lblcanvas.mouse.motion)
      imgx, imgy = imgcoords(btn, can, zr)
      ns = nearestspotidx(lbl, (imgx, imgy))
      if ns != nothing
        coords = lbl[ns]
        x, y = canvascoords(coords, can, zr)
        Graphics.set_source_rgb(ctx, config.selectedspotcolor...)
        Graphics.arc(ctx, x, y, 1.5config.spotradius, 0, 2pi)
        Graphics.stroke(ctx)
      end
    end
    
    # Clear the surface if labels should not be shown
    if !sl
      ctx = Graphics.getgc(can)
      Graphics.save(ctx)
      Cairo.set_operator(ctx, Cairo.OPERATOR_CLEAR)
      Graphics.paint(ctx)
      Graphics.restore(ctx)
    end
  end)
end


function initcounting(currentframe, threshold, mergedist)
  # Signal that gets updated if the current label changes 
  lbl = map(currentframe, typ=Any) do frame
    if frame != nothing
      return frame.label
    end
  end
  # Signal that is updated if the current density map 
  dens = map(currentframe, typ=Any) do frame
    if frame != nothing
      return frame.density
    end
  end
  foreach(dens, threshold, mergedist) do density, thr, dist
    if density != nothing
      cf = value(currentframe)
      cf.autolabel = declutter(DCellC.label(density, level=thr), dist)
    end
    return nothing
  end
  return lbl, dens
end



# ---------------------------------------------------------------------------- #
# TODO: Stuff that may be needed/implemented later

function zoomregionadapt(canvas, zr)
  cv = zr.currentview
  width  = GtkReactive.width(canvas)
  height = GtkReactive.height(canvas)
  zwidth  = - (-(cv.x...))
  zheight = - (-(cv.y...))
  aspect = min(zwidth / width, zheight / height)
  rz.currentview.x = (cv.x[1], cv.y[1] + round(Int, aspect * width))
  rz.currentview.y = (cv.y[1], cv.y[1] + round(Int, aspect * height))
end

function cumulativehist(image)
  return []
end

