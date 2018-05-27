

# ---------------------------------------------------------------------------- #
# Dialogs like adding new frames

function addframedialog(root, button)
  return map(button, init=String[]) do _
    tif = "image/tiff"
    filter = GtkFileFilter(name="Tiff format", mimetype=tif)
    return open_dialog("Choose image files to import", 
                     root, (filter,), select_multiple = true)
  end
end

function addmodeldialog(root, button)
  return map(button, init=String[]) do _
    ext = "*.dccm"
    return open_dialog("Choose models to load",
                       root, (ext,), select_multiple = true)
  end
end

function savemodeldialog(root, button)
  return map(button, init="") do _
    ext = "*.dccm"
    return save_dialog("Save model as", root, (ext,))
  end
end

function exportlessondialog(root, button)
  return map(button, init="") do _
    ext = "*.dcct"
    return save_dialog("Export lesson as", root, (ext,))
  end
end

function trainedmodeldialog(root, button)
  return map(button, init="") do _
    ext = "*.dccm"
    return save_dialog("Save trained model as", root, (ext,))
  end
end
