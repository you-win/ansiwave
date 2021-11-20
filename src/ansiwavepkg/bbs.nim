from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./ui/editor import nil
from ./ui/navbar import nil
from ./constants import nil
import pararules
from pararules/engine import Session, Vars
from json import JsonNode
import tables
from ./crypto import nil
from ./storage import nil
from wavecorepkg/paths import nil
from ./post import CommandTreesRef
from times import nil
from ./midi import nil

type
  Id* = enum
    Global,
  Attr* = enum
    SelectedPage, AllPages, PageBreadcrumbs, PageBreadcrumbsIndex,
    Signature, ComponentData, FocusIndex, ScrollY,
    View, ViewCommands, ViewHeight, ViewFocusAreas, MidiProgress,
  Component = ui.Component
  ViewFocusAreaSeq = seq[ui.ViewFocusArea]
  Page = tuple
    id: int
    sig: string
    data: Component
    focusIndex: int
    scrollY: int
    view: JsonNode
    viewCommands: CommandTreesRef
    viewHeight: int
    viewFocusAreas: ViewFocusAreaSeq
    midiProgress: MidiProgressType
  PageTable = ref Table[string, Page]
  PageBreadcrumbsType = seq[string]
  MidiProgressType = ref object
    midiResult: midi.PlayResult
    time: tuple[start: float, stop: float]

schema Fact(Id, Attr):
  SelectedPage: string
  AllPages: PageTable
  PageBreadcrumbs: PageBreadcrumbsType
  PageBreadcrumbsIndex: int
  Signature: string
  ComponentData: Component
  FocusIndex: int
  ScrollY: int
  View: JsonNode
  ViewCommands: CommandTreesRef
  ViewHeight: int
  ViewFocusAreas: ViewFocusAreaSeq
  MidiProgress: MidiProgressType

type
  BbsSession* = Session[Fact, Vars[Fact]]

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, SelectedPage, selectedPage)
        (Global, AllPages, pages)
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
    rule changeSelectedPage(Fact):
      what:
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
      then:
        session.insert(Global, SelectedPage, breadcrumbs[breadcrumbsIndex])
    rule getPage(Fact):
      what:
        (id, Signature, sig)
        (id, ComponentData, data)
        (id, FocusIndex, focusIndex)
        (id, ScrollY, scrollY)
        (id, View, view)
        (id, ViewCommands, viewCommands)
        (id, ViewHeight, viewHeight)
        (id, ViewFocusAreas, viewFocusAreas)
        (id, MidiProgress, midiProgress)
      thenFinally:
        var t: PageTable
        new t
        for page in session.queryAll(this):
          t[page.sig] = page
        session.insert(Global, AllPages, t)

proc goToPage(session: var auto, sig: string) =
  let globals = session.query(rules.getGlobals)
  var breadcrumbs = globals.breadcrumbs
  if globals.breadcrumbsIndex < breadcrumbs.len - 1:
    breadcrumbs = breadcrumbs[0 .. globals.breadcrumbsIndex]
  breadcrumbs.add(sig)
  session.insert(Global, PageBreadcrumbs, breadcrumbs)
  session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex + 1)

var
  nextPageId = Id.high.ord + 1
  sigToPageId: Table[string, int]

proc insertPage(session: var auto, comp: ui.Component, sig: string) =
  let id =
    if sigToPageId.hasKey(sig):
      sigToPageId[sig]
    else:
      let n = nextPageId
      sigToPageId[sig] = n
      nextPageId += 1
      n
  session.insert(id, Signature, sig)
  session.insert(id, ComponentData, comp)
  session.insert(id, FocusIndex, 0)
  session.insert(id, ScrollY, 0)
  session.insert(id, View, cast[JsonNode](nil))
  session.insert(id, ViewCommands, cast[CommandTreesRef](nil))
  session.insert(id, ViewHeight, 0)
  session.insert(id, ViewFocusAreas, @[])
  session.insert(id, MidiProgress, cast[MidiProgressType](nil))
  session.goToPage(sig)

proc initSession*(c: client.Client): auto =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Global, SelectedPage, "")
  result.insert(Global, AllPages, cast[PageTable](nil))
  let breadcrumbs: PageBreadcrumbsType = @[]
  result.insert(Global, PageBreadcrumbs, breadcrumbs)
  result.insert(Global, PageBreadcrumbsIndex, -1)
  result.insertPage(ui.initUser(c, paths.sysopPublicKey), paths.sysopPublicKey)
  result.fireRules

proc handleAction(session: var auto, clnt: client.Client, comp: ui.Component, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], actionName: string, actionData: OrderedTable[string, JsonNode]): bool =
  case actionName:
  of "show-replies":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right}
    if result:
      let
        sig = actionData["sig"].str
        globals = session.query(rules.getGlobals)
      if globals.pages.hasKey(sig):
        session.goToPage(sig)
      else:
        session.insertPage(ui.initPost(clnt, sig), sig)
  of "show-editor":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right}
    if result:
      let
        sig = actionData["sig"].str
        headers = actionData["headers"].str
        globals = session.query(rules.getGlobals)
      if globals.pages.hasKey(sig):
        session.goToPage(sig)
      else:
        session.insertPage(ui.initEditor(width, height, sig, headers), sig)
  of "edit":
    result = input.key notin {iw.Key.Escape}
  of "create-user":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      crypto.createUser()
      let globals = session.query(rules.getGlobals)
      session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  of "add-user":
    when defined(emscripten):
      result = input.key in {iw.Key.Mouse, iw.Key.Enter}
      if result:
        var sess = session
        crypto.browsePrivateKey(proc () =
          let globals = sess.query(rules.getGlobals)
          if globals.breadcrumbsIndex > 0:
            sess.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
        )
  of "go-back":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      let globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  of "logout":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      crypto.removeKey()
      let globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  else:
    discard

proc renderHtml*(session: auto): string =
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
  ui.toHtml(page.data)

proc isEditor(page: Page): bool =
  page.data.kind == ui.Editor

proc isEditor*(session: auto): bool =
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
  page.isEditor

proc init*() =
  try:
    crypto.loadKey()
  except Exception as ex:
    echo ex.msg
  when defined(emscripten):
    midi.fetchSoundfont()

proc render*(session: var auto, clnt: client.Client, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], finishedLoading: var bool): iw.TerminalBuffer =
  session.fireRules
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
    maxScroll = max(1, int(height / 5))
    view =
      if page.view == nil:
        let v = ui.toJson(page.data, finishedLoading)
        if finishedLoading:
          session.insert(page.id, View, v)
          var cmds: CommandTreesRef
          new cmds
          cmds[] = post.linesToTrees(ui.getContent(page.data))
          session.insert(page.id, ViewCommands, cmds)
        v
      else:
        page.view
    isPlaying =
      if page.isEditor:
        editor.isPlaying(page.data.session)
      else:
        page.midiProgress != nil

  var sess = session
  let
    backAction = proc () {.closure.} =
      if globals.breadcrumbsIndex > 0:
        sess.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
    refreshAction = proc () {.closure.} =
      sess.insert(page.id, View, cast[JsonNode](nil))
      sess.insert(page.id, ViewFocusAreas, @[])
      sess.insert(page.id, ViewHeight, 0)
      ui.refresh(clnt, page.data)
    searchAction = proc () {.closure.} =
      discard
    copyAction = proc () {.closure.} =
      discard
    sendAction = proc () {.closure.} =
      editor.setEditable(page.data.session, false)
      let (body, sig) = crypto.sign(page.data.headers, editor.getContent(page.data.session))
      page.data.requestBody = body
      page.data.requestSig = sig
      page.data.request = client.submit(clnt, "ansiwave", body)
    loginAction = proc () {.closure.} =
      sess.insertPage(ui.initLogin(), "login")
    logoutAction = proc () {.closure.} =
      sess.insertPage(ui.initLogout(), "logout")
    myPageAction = proc () {.closure.} =
      sess.insertPage(ui.initUser(clnt, crypto.pubKey), crypto.pubKey)
    downloadKeyAction = proc () {.closure.} =
      when defined(emscripten):
        crypto.downloadKey()

  # if there is any input, find the associated action
  var
    action: tuple[actionName: string, actionData: OrderedTable[string, JsonNode]]
    focusIndex = page.focusIndex
    scrollY = page.scrollY
  if (input.key != iw.Key.None or input.codepoint > 0) and page.focusIndex < page.viewFocusAreas.len:
    if input.key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
        for i in 0 ..< page.viewFocusAreas.len:
          let area = page.viewFocusAreas[i]
          if info.x >= area.left and
              info.x <= area.right and
              info.y + scrollY >= area.top and
              info.y + scrollY <= area.bottom - 1:
            action = (area.action, area.actionData)
            focusIndex = i
            break
    else:
      let area = page.viewFocusAreas[page.focusIndex]
      action = (area.action, area.actionData)

  # handle the action
  if not handleAction(session, clnt, page.data, width, height, input, action.actionName, action.actionData):
    case input.key:
    of iw.Key.Up:
      if page.focusIndex > 0:
        focusIndex = page.focusIndex - 1
    of iw.Key.Down:
      focusIndex = page.focusIndex + 1
    of iw.Key.Left, iw.Key.Escape:
      if not isPlaying:
        backAction()
        # since we have changed the page, we need to rerun this function from the beginning
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
    else:
      discard
    # adjust focusIndex and scrollY based on viewFocusAreas
    if page.viewFocusAreas.len > 0:
      # don't let it go beyond the last focused area
      if focusIndex > page.viewFocusAreas.len - 1:
        focusIndex = page.viewFocusAreas.len - 1
      # when going up or down, if the next focus area's edge is
      # beyond the current viewable scroll area, adjust scrollY
      # so we can see it. if the adjustment is greater than maxScroll,
      # only scroll maxScroll rows and update the focusIndex.
      case input.key:
      of iw.Key.Up:
        if page.viewFocusAreas[focusIndex].top < page.scrollY + navbar.height:
          scrollY = page.viewFocusAreas[focusIndex].top - navbar.height
          let limit = page.scrollY - maxScroll
          if scrollY < limit:
            scrollY = limit
          if page.viewFocusAreas[focusIndex].bottom < scrollY:
            focusIndex += 1
      of iw.Key.Down:
        if page.viewFocusAreas[focusIndex].bottom > page.scrollY + height:
          scrollY = page.viewFocusAreas[focusIndex].bottom - height
          let limit = page.scrollY + maxScroll
          if scrollY > limit:
            scrollY = limit
          if page.viewFocusAreas[focusIndex].top > scrollY + height:
            focusIndex -= 1
      else:
        discard

  # render
  var
    y = - scrollY + navbar.height
    areas: seq[ui.ViewFocusArea]
  if page.isEditor:
    result = iw.newTerminalBuffer(width, height)
    editor.tick(page.data.session, result, 0, navbar.height, width, height - navbar.height, input, finishedLoading)
    ui.render(result, view, 0, y, focusIndex, areas)
    var rightButtons: seq[(string, proc ())]
    var errorLines: seq[string]
    if page.data.request.chan != nil:
      client.get(page.data.request)
      if not page.data.request.ready:
        rightButtons.add((" sending... ", proc () {.closure.} = discard))
        finishedLoading = false # when a request is being sent, make sure the view refreshes
      elif page.data.request.value.kind == client.Valid:
        session.retract(page.id, ComponentData)
        storage.remove(page.sig & ".ansiwave")
        backAction()
        session.fireRules
        if storage.set(page.data.requestSig & ".post.ansiwave", page.data.requestBody):
          session.insertPage(ui.initPost(clnt, page.data.requestSig), page.data.requestSig)
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
      else:
        let continueAction = proc () =
          page.data.request.chan = nil
          editor.setEditable(page.data.session, true)
        rightButtons.add((" continue editing ", continueAction))
        errorLines = @["Error", page.data.request.value.error]
    else:
      rightButtons.add((" send ", sendAction))
    if not isPlaying:
      navbar.render(result, 0, 0, input, [(" ← ", backAction)], errorLines, rightButtons)
    page.data.session.fireRules
    editor.saveToStorage(page.data.session, page.sig)
  else:
    result = iw.newTerminalBuffer(width, when defined(emscripten): page.viewHeight else: height)
    ui.render(result, view, 0, y, focusIndex, areas)
    var leftButtons = @[(" ← ", backAction), (" ⟳ ", refreshAction), (" search ", searchAction)]
    when not defined(emscripten):
      leftButtons.add((" copy link ", copyAction))
    var tb = result
    let
      renderMidiProgress =
        proc (progress: float) =
          iw.fill(tb, 0, 0, constants.editorWidth + 1, 2, " ")
          iw.fill(tb, 0, 0, int(progress * float(constants.editorWidth + 1)), 0, "▓")
          iw.write(tb, 0, 1, "press tab to stop playing")
          if iw.gIllwillInitialised:
            iw.display(tb)
      startRenderingMidiProgress =
        proc (midiResult: midi.PlayResult) =
          let currTime = times.epochTime()
          var progress: MidiProgressType
          new progress
          progress.midiResult = midiResult
          progress.time = (currTime, currTime + midiResult.secs)
          sess.insert(page.id, MidiProgress, progress)
    if page.midiProgress != nil:
      let currTime = times.epochTime()
      if currTime > page.midiProgress[].time.stop or input.key in {iw.Key.Tab, iw.Key.Escape}:
        midi.stop(page.midiProgress[].midiResult.playResult.addrs)
        session.insert(page.id, MidiProgress, cast[MidiProgressType](nil))
      else:
        renderMidiProgress((currTime - page.midiProgress[].time.start) / (page.midiProgress[].time.stop - page.midiProgress[].time.start))
    else:
      if page.viewCommands != nil and page.viewCommands[].len > 0 and page.midiProgress == nil:
        let
          playAction = proc () {.closure.} =
            try:
              if iw.gIllwillInitialised:
                post.compileAndPlayAll(page.viewCommands[], renderMidiProgress)
              else:
                post.compileAndPlayAll(page.viewCommands[], startRenderingMidiProgress)
            except Exception as ex:
              discard
        leftButtons.add((" ♫ play ", playAction))
      var rightButtons: seq[(string, proc ())] =
        if page.sig == "login" or page.sig == "logout":
          @[]
        elif crypto.pubKey == "":
          @[(" login ", loginAction)]
        elif page.sig == crypto.pubKey:
          when defined(emscripten):
            @[(" download login key ", downloadKeyAction), (" logout ", logoutAction)]
          else:
            @[(" logout ", logoutAction)]
        else:
          @[(" my page ", myPageAction)]
      navbar.render(result, 0, 0, input, leftButtons, [], rightButtons)

  # update values if necessary
  if focusIndex != page.focusIndex:
    session.insert(page.id, FocusIndex, focusIndex)
  if scrollY != page.scrollY:
    session.insert(page.id, ScrollY, scrollY)
  # we can't update view info after scrolling, or the y values will be incorrect
  if scrollY == 0 and (page.viewFocusAreas != areas or page.viewHeight != y):
    session.insert(page.id, ViewFocusAreas, areas)
    session.insert(page.id, ViewHeight, y)
    # if the view height has changed, emscripten needs to render again
    when defined(emscripten):
      if y != page.viewHeight:
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $paths.port & "/" & paths.boardsDir & "/" & paths.sysopPublicKey & "/" & paths.dbDir & "/" & paths.dbFilename
  vfs.register()
  var clnt = client.initClient(paths.address)
  client.start(clnt)
  init()

  # create session
  var session = initSession(clnt)

  # start loop
  while true:
    var finishedLoading = false
    var tb = render(session, clnt, iw.terminalWidth(), iw.terminalHeight(), (iw.getKey(), 0'u32), finishedLoading)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

