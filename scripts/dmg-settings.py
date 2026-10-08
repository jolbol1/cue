# dmgbuild settings for Cue's drag-to-Applications disk image.
# Used by scripts/package.sh; `defines` comes from dmgbuild's -D options.
app = defines.get("app", "dist/Cue.app")  # noqa: F821

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = "Resources/Cue.icns"

# No background image, so the window follows the viewer's light or dark appearance.
window_rect = ((200, 200), (540, 340))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_sidebar = False
show_pathbar = False
show_icon_preview = False
icon_size = 128
text_size = 13
icon_locations = {"Cue.app": (140, 150), "Applications": (400, 150)}
