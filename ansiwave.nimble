# Package

version       = "1.2.2"
author        = "oakes"
description   = "ANSI art + MIDI music"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim", "ansiwave", "c", "h", "m"]
bin           = @["ansiwave"]

task dev, "Run dev version":
  # this sets release mode because playing music
  # is unstable in debug builds for some reason
  exec "nimble -d:release run ansiwave tests/variables.ansiwave"

task bbs, "Run bbs test":
  exec "nimble run ansiwave http://localhost:3000"

# Dependencies

requires "nim >= 1.4.2"
requires "pararules >= 0.20.0"
requires "paramidi >= 0.6.0"
requires "paramidi_soundfonts >= 0.2.0"
requires "parasound >= 0.2.0"
requires "zippy >= 0.5.5"
requires "stb_image >= 2.5"
requires "wavecore >= 0.2.1"
requires "chrono >= 0.3.0"
