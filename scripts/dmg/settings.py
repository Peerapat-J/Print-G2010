# Window layout of the disk image, read by dmgbuild. scripts/make-dmg.sh passes the app and this
# folder with -D app=... -D assets=... The positions match the arrow drawn by
# scripts/make-dmg-background.swift.
import os

app = defines["app"]  # noqa: F821 - `defines` is provided by dmgbuild
assets = defines["assets"]  # noqa: F821

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

# dmgbuild picks up background@2x.png next to this file for Retina screens.
background = os.path.join(assets, "background.png")

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
icon_size = 128
text_size = 13
arrange_by = None

icon_locations = {
    os.path.basename(app): (180, 190),
    "Applications": (480, 190),
}
hide_extensions = [os.path.basename(app)]
