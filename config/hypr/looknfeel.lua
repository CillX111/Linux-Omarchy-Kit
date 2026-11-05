-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Fenster immer nebeneinander öffnen (Spalten), mit SUPER + Pfeile wechseln.
hl.config({
  general = {
    layout = "scrolling",
  },
})

-- ===== "Cooler" Look (2026-11-04) =====
-- Runde Ecken, weiche Schatten, Glas-Unschärfe, schwungvollere Animationen
-- und ein langsam drehender Lichtrand ums aktive Fenster.
hl.config({
  general = {
    col = {
      active_border = { colors = { "rgba(ffffffee)", "rgba(8d8d8d55)", "rgba(ffffffee)" }, angle = 45 },
      inactive_border = "rgba(40404066)",
    },
  },
  decoration = {
    rounding = 12,
    rounding_power = 2.6,
    shadow = {
      enabled = true,
      range = 22,
      render_power = 3,
      color = "rgba(000000aa)",
    },
    blur = {
      enabled = true,
      size = 5,
      passes = 2,
      vibrancy = 0.25,
      noise = 0.015,
      popups = true,
    },
  },
})

hl.curve("snappy", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.08 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.5, bezier = "snappy", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.5, bezier = "snappy" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.2, bezier = "easeOutQuint", style = "slidefade 18%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slidevert" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 60, bezier = "linear", style = "loop" })

-- Startmenü (SUPER + SPACE): nur hinter der Karte weichzeichnen (Glas), Rest nur leicht abgedunkelt
hl.layer_rule({ match = { namespace = "cillian-start" }, blur = true, ignore_alpha = 0.5, no_anim = true, animation = "none" })

-- Glas-Leiste oben (Plugin cillian.leiste): Hintergrund hinter der Kapsel weichzeichnen.
-- ignore_alpha: nur die Kapsel selbst (nicht der weiche Schatten darunter) bekommt Blur.
hl.layer_rule({ match = { namespace = "cillian-leiste" }, blur = true, ignore_alpha = 0.45, no_anim = true })

-- Kalender-Foto (Plugin cillian.kalender): Glas-Blur nur hinter der Karte, eigene Einblendung
hl.layer_rule({ match = { namespace = "cillian-kalender" }, blur = true, ignore_alpha = 0.45, no_anim = true, animation = "none" })

-- Leisten-Fenster (Audio, WLAN, Bluetooth ...): Glas-Blur hinter der Karte.
-- Die Ebene ist bildschirmgross und sonst durchsichtig -> ignore_alpha, damit nur die Karte weichzeichnet.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.3 })

-- Einheitlicher Glas-Stil (shell.toml, 2026-11-05): Blur hinter allen Shell-Karten.
-- Die Ebenen sind teils bildschirmgross (Abdunkelung 0.22) -> ignore_alpha 0.3, damit
-- nur die Karten (0.78) weichzeichnen, nicht der ganze Bildschirm.
hl.layer_rule({ match = { namespace = "^(omarchy-menu|omarchy-clipboard|omarchy-emojis|omarchy-polkit|omarchy-osd|omarchy-reminders|omarchy-network-qr)$" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "omarchy-notifications" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "cillian-music" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "omarchy-image-selector" }, blur = true, ignore_alpha = 0.3 })
-- Glas-Stil auch für Passwort-Balken (sudo, Teams-Sperre) und "Monitore anordnen"
hl.layer_rule({ match = { namespace = "^(sudo-prompt|teams-lock|cillian-monitore|cillian-monitore-id)$" }, blur = true, ignore_alpha = 0.3 })
