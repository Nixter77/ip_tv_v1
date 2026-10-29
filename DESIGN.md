---
name: IPTV Player
description: macOS IPTV catalog and player. Warm paper chrome, dark video well, severity banners.
colors:
  ink: "#1C1915"
  paper: "#F7F4EE"
  video: "#0C0C0C"
  hudInk: "#FFFFFF"
  live: "#B42318"
  favorite: "#9D174D"
  info: "#0F5C45"
  infoWash: "#E7F0EA"
  warning: "#7A4E00"
  warningWash: "#F8E8C8"
  error: "#9F1D1D"
  errorWash: "#FAE2DE"
  primary: "#1C1915"
typography:
  caption:
    fontFamily: SF Pro
    fontSize: 11px
    fontWeight: 400
    lineHeight: 1.3
  body:
    fontFamily: SF Pro
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.4
  title:
    fontFamily: SF Pro
    fontSize: 17px
    fontWeight: 600
    lineHeight: 1.3
rounded:
  s: 4px
  m: 6px
  row: 8px
  hud: 16px
spacing:
  xxs: 2px
  xs: 4px
  s: 6px
  m: 8px
  l: 12px
  xl: 16px
  xxl: 20px
components:
  status-info:
    backgroundColor: "{colors.infoWash}"
    textColor: "{colors.info}"
    rounded: "{rounded.m}"
    padding: "{spacing.m}"
  status-warning:
    backgroundColor: "{colors.warningWash}"
    textColor: "{colors.warning}"
    rounded: "{rounded.m}"
    padding: "{spacing.m}"
  status-error:
    backgroundColor: "{colors.errorWash}"
    textColor: "{colors.error}"
    rounded: "{rounded.m}"
    padding: "{spacing.m}"
  channel-row:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.row}"
    padding: "{spacing.m}"
  video-well:
    backgroundColor: "{colors.video}"
    textColor: "{colors.hudInk}"
    rounded: "{rounded.hud}"
    padding: "{spacing.l}"
  live-badge:
    backgroundColor: "{colors.live}"
    textColor: "{colors.hudInk}"
    rounded: "{rounded.s}"
    padding: "{spacing.xs}"
  favorite-mark:
    backgroundColor: "{colors.favorite}"
    textColor: "{colors.hudInk}"
    rounded: "{rounded.s}"
    padding: "{spacing.xs}"
---

# Overview

IPTV Player is a macOS SwiftUI app for browsing an iptv-org catalog and playing a stream. The window uses the system unified toolbar. The video surface stays dark. Catalog chrome stays on warm paper. Status messages use three severities: info, warning, and error.

# Colors

Ink `#1C1915` on paper `#F7F4EE` is the default text pair. The video well is `#0C0C0C` with white HUD text. Live is `#B42318`. Favorite is `#9D174D`. Info, warning, and error each have a dark text color on a light wash so the banner stays readable in light and dark windows.

# Typography

The UI uses the system San Francisco face. Captions are 11px, body is 13px, titles are 17px. Weights are regular 400 and semibold 600. Line height stays tight because the sidebar and channel rows are dense.

# Layout

Spacing steps are 2, 4, 6, 8, 12, 16, and 20. The channel list pages 400 rows and offers another page. The video view leaves the traffic-light band clickable. Search focus stays in the channel list. The sidebar lists only countries, languages, and categories that contain at least one visible channel, each with a count.

# Elevation

The HUD is a single floating panel over the video well. It uses the system HUD material and a hairline white stroke. Rows do not lift or scale on hover. A hover only changes the row wash.

# Shapes

Corners are 4, 6, 8, and 16. Rows use 8. The HUD uses 16. Status banners use 6.

# Components

The status banner switches icon, text, and wash for info, warning, and error. Channel rows show a logo, name, and favorite mark. The video well hosts playback. The live badge and favorite mark sit on the dark video colors with white text.

# Do's and Don'ts

Do take color and spacing from these tokens. Do keep NSFW and closed channels hidden until the user turns them on. Do show a count beside every sidebar group that has channels. Don't hardcode palette colors or spacing numbers in views. Don't scale a row on hover. Don't put a hidden title bar with a manual top pad over the traffic lights. Don't pass search focus state across views.
