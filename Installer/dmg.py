# The disk image's layout, for dmgbuild (https://github.com/dmgbuild/dmgbuild),
# which writes the Finder's own layout file directly: no Finder to script and no
# window opening mid-build. build.sh passes the paths in with -D.
#
# The places here are the ones Installer/background.swift draws around —
# change one, change the other.

import os.path

app = defines["app"]
name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]                  # the mounted volume wears the app's icon
background = defines["background"]

# 640 x 380 of content under a title bar of about 32.
window_rect = ((200, 160), (640, 412))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    name: (180, 145),
    "Applications": (460, 145),
}
