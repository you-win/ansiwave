import unittest
import ansiwave
import strutils

test "Dedupe codes":
  const text = "\e[31m\e[32m\e[41;42;43mHello, world!\e[31m"
  let newText = text.dedupeCodes
  check newText.escape == "\e[32;43mHello, world!\e[31m".escape

import ansiwavepkg/wavescript

test "Parse commands":
  const text = strutils.splitLines(staticRead("hello.ansiwave"))
  let cmds = text.parse
  check cmds.len == 2
  for cmd in cmds:
    echo cmd.parse
