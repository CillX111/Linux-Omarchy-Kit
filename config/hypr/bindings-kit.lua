-- >>> Linux-Omarchy-Kit (Tasten für die Kit-Plugins)
-- SUPER + SPACE -> Startmenü (das Omarchy-Menü bleibt auf SUPER + ALT + SPACE / SUPER + ESC)
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Startmenü", "omarchy-shell shell toggle cillian.start")
-- Page_Up -> Musik-Panel unten links (nochmal drücken = zu)
o.bind("Page_Up", "Musik-Panel", "omarchy-shell shell toggle cillian.music")
-- SUPER + ALT + D -> Monitore anordnen wie in Windows
o.bind("SUPER + ALT + D", "Monitore anordnen", "~/.local/bin/monitore-anordnen")
-- <<< Linux-Omarchy-Kit
