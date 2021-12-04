from ../illwill as iw import `[]`, `[]=`
from ../constants import nil
from ./editor import nil
import unicode

const height* = 3

proc renderButton(tb: var iw.TerminalBuffer, text: string, x: int, y: int, key: iw.Key, cb: proc (), focused: bool, shortcut: tuple[key: set[iw.Key], hint: string] = ({}, "")): int =
  result = x + text.runeLen + 1
  let endY = y + height - 1
  iw.drawRect(tb, x, y, result, endY, doubleStyle = focused)
  iw.write(tb, x + 1, y + 1, text)
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.x >= x and
          info.x <= result and
          info.y >= y and
          info.y <= endY:
        cb()
  elif (key == iw.Key.Enter and focused) or key in shortcut.key:
    cb()
  result += 1

proc render*(tb: var iw.TerminalBuffer, pageX: int, pageY: int, input: tuple[key: iw.Key, codepoint: uint32], leftButtons: openArray[(string, proc())], middleLines: openArray[string], rightButtons: openArray[(string, proc())], focusIndex: var int) =
  let buttonCount = leftButtons.len + rightButtons.len
  case input.key:
  of iw.Key.Right:
    if focusIndex < 0 and abs(focusIndex) < buttonCount:
      focusIndex -= 1
  of iw.Key.Left:
    if focusIndex < -1:
      focusIndex += 1
  else:
    discard

  iw.fill(tb, pageX, pageY, pageX + constants.editorWidth + 1, pageY + height - 1)
  var lineY = pageY
  for line in middleLines:
    if unicode.validateUtf8(line) == -1:
      iw.write(tb, max(pageX, int(constants.editorWidth.float / 2 - line.len / 2)), lineY, line)
      lineY += 1
  var buttonFocus = -1
  var x = pageX
  for (text, cb) in leftButtons:
    x = renderButton(tb, text, x, pageY, input.key, cb, buttonFocus == focusIndex)
    buttonFocus -= 1
  var rightButtonWidth = 0
  for (text, cb) in rightButtons:
    rightButtonWidth += text.runeLen + 2
  x = (constants.editorWidth + 2) - rightButtonWidth
  for (text, cb) in rightButtons:
    x = renderButton(tb, text, x, pageY, input.key, cb, buttonFocus == focusIndex)
    buttonFocus -= 1

