
# ---------------------------------------------------------------------------- #
# Update general information


function initgeneralinfo(currentframe, infoname, infotype, infores, comment)
  foreach(currentframe) do frame
    if frame != nothing
      push!(infoname, frame.name)
      push!(infotype, splitext(frame.name)[2][2:end])
      push!(infores, (@sprintf("%4d x %4d", size(frame.source)...)))
      push!(comment, frame.comment)
    else
      push!(infoname, "--")
      push!(infotype, "--")
      push!(infores, "--")
      push!(comment, "")
    end
  end
  foreach(comment) do com
    frame = value(currentframe)
    if frame != nothing
      frame.comment = com
    end
    return nothing
  end
end



