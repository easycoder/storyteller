!!  Tabbed script editor with auto-save and external change detection.
!!  Served by server.as locally, or any web server with /list, /read, /write routes.
!   asedit.as

    script ASEditor
!! @hash 7ad312d2
!!!
!! Variable declarations
!! The script uses a lot of variables; they are grouped here by function.
!   -- DOM --
    div Body
    div TabBar
    div TabBtn
    div Overlay
    div Scroller
    div FileRow
    div EditorArea       ! flat-mode pane (CodeMirror-wrapped textarea)
    div BlocksArea       ! Blocks-mode pane (toolbar + split)
    textarea ContentEditor
    textarea BlocksCodePane
    textarea BlocksDocPane
    span StatusSpan
    span TabLabel
    span BlocksTitle
    span BlocksBadge
    button OpenBtn
    button FindBtn
    button BlocksBtn
    button BlocksPrev
    button BlocksNext
    button BlocksVerify
    button CloseBtn
    img PlusBtn
    img TabClose
    a FileName
    pre UIPre

!   -- State --
    variable Lang
    variable StrOpen
    variable StrFind
    variable StrClose
    variable StrSaved
    variable StrSaveFailed
    variable StrReloaded
    variable StrExtChange
    variable StrNoConnect
    variable StrSaveAs
    variable StrEmpty
    variable StrUpLevel
    variable StrRoot
    variable StrUpdated
    variable StrRestart
    variable TabPath       ! array: full file path per tab (relative to project root)
    variable TabName       ! array: display name (basename) per tab
    variable TabSaved      ! array: last content saved to server per tab
    variable TabCount
    variable ActiveTab
    variable Content       ! scratch: current editor content
    variable FileContent   ! scratch: content fetched from server
    variable FileList      ! scratch: JSON array from /list
    variable N
    variable M
    variable Item          ! scratch: single entry object from list
    variable File          ! scratch: single filename
    variable FileCount
    variable TabItem
    variable UIWebson
    variable VersionResult
    variable CurrentPath   ! current directory being browsed (relative, no leading /)
    variable EntryName
    variable EntryType

!   -- Blocks mode (parser + view + edit) --
    variable BlocksMode    ! 0 = flat, 1 = Blocks pane visible
    variable CurBlock      ! 0-based index into Sections arrays
    variable BlockDirty    ! 1 if user edited the current block since last splice
    variable SecCount      ! number of parsed sections
    variable SecStart      ! array: 1-based opener line number
    variable SecEnd        ! array: 1-based terminator line number
    variable SecProse      ! array: prose text (one entry, joined by newline, !! prefix stripped)
    variable SecCode       ! array: code text (joined by newline, verbatim)
    variable SecHash       ! array: stored @hash, or empty
    variable SecVerified   ! array: stored @verified, or empty
    variable SecHashState  ! array: fresh / stale / no-baseline / no-code
    variable SecVerifyState ! array: verified-fresh / verified-stale / unverified / verified-no-code

!   -- Parser scratch (rebuilt every parse) --
    variable Lines         ! source split on newline
    variable LineCount
    variable Line
    variable Kind          ! `TERM`, `DOC`, `META`, `CODE`
    variable LContent      ! body of a DOC/META line
    variable MetaKey
    variable MetaValue
    variable Pos
    variable Tmp
    variable InSection
    variable SecHasCode
    variable SecStartTmp
    variable SecCodeTmp
    variable SecProseTmp
    variable SecHashTmp
    variable SecVerifiedTmp
    variable CurHash
    variable HashState
    variable VerifyState
    variable I
    variable Source        ! whole source text being parsed
    variable Outside       ! array: text between sections (length SecCount + 1)
    variable OutsideTmp    ! accumulator for the current outside chunk
    variable ProseSrc      ! scratch: prose text being split into lines
    variable PCount        ! scratch: count of prose lines
    variable PJ            ! scratch: index over prose lines
    variable PL            ! scratch: one prose line
    variable BlkText       ! scratch: assembled section text
    variable NewProse      ! scratch: edited prose pulled from BlocksDocPane
    variable NewCode       ! scratch: edited code pulled from BlocksCodePane
    variable OldProse      ! scratch: previously stored prose for this section
    variable OldCode       ! scratch: previously stored code for this section

!   -- Blocks: TOC + draggable divider --
    div BlocksToc          ! left sidebar listing all blocks
    div BlocksDivider      ! draggable splitter between code and doc panes
    div TocRow             ! one row per block in the TOC
    span TocLabel          ! the clickable label inside each TocRow
    variable PickPos       ! pick coords at mousedown on divider
    variable DragPos       ! drag coords during mousemove
    variable PickX
    variable DragX
    variable CodeWidthAtPick
    variable NewWidth
    variable StoredWidth
    variable FinalWidth
    variable FirstLine     ! first prose line of a block (for TOC label)
    variable NL
    variable J
!! @hash 74f1e5a5
!! @verified 82dc7ca8
!!!
!! The UI is described by a DOM element 'asedit-ui',
!! a <pre> element that contains all the DOM elements that go to make up the editor.
!! These are formatted using Webson, a JSON representation of any number of DOM elements,
!! which is rendered into an existing element using the 'render' command
!! 'body' without a capital, is the HTML <body> element
!! 'Body', where the first letter is a capital, is a variable that is attached to the page body
!! so that other elements - in this case those represented by the Webson -  can be added to it.
!   -- Build UI --
    attach Body to body
    attach UIPre to `asedit-ui`
    put the content of UIPre into UIWebson
    render UIWebson in Body
    attach TabBar to `se-tabbar`
    attach ContentEditor to `se-textarea`
    attach StatusSpan to `se-status`
    attach OpenBtn to `se-open`
    attach FindBtn to `se-findbtn`
    attach PlusBtn to `se-plusbtn`
    attach Overlay to `se-overlay`
    attach Scroller to `se-scroller`
    attach CloseBtn to `se-closebtn`
    attach BlocksBtn to `se-blocksbtn`
    attach EditorArea to `se-editor-area`
    attach BlocksArea to `se-blocks-area`
    attach BlocksTitle to `se-blocks-title`
    attach BlocksPrev to `se-blocks-prev`
    attach BlocksNext to `se-blocks-next`
    attach BlocksBadge to `se-blocks-badge`
    attach BlocksVerify to `se-blocks-verify`
    attach BlocksCodePane to `se-blocks-code`
    attach BlocksDocPane to `se-blocks-doc`
    attach BlocksToc to `se-blocks-toc`
    attach BlocksDivider to `se-blocks-divider`
!! @hash 21eabec3
!! @verified 9fa497ac
!!!
!! Some general initialisation
!   -- CodeMirror --
    codemirror attach to ContentEditor

    put 0 into TabCount
    put 0 into ActiveTab
    put `` into CurrentPath
!! @hash 3a601096
!! @verified 3a601096
!!!
!! Language detection
!! The command 'language xx' switches the system to the given language (fr, de, it etc.)
!! and defaults to 'en'. All of the language-specific strings are then defined for each language.
!   -- Detect language and set strings for each supported language --
    div LangDiv
    put `en` into Lang
    attach LangDiv to `editor-lang` or go to SetStrings
    put the text of LangDiv into Lang
    replace ` ` with `` in Lang
    replace newline with `` in Lang
    if Lang is empty put `en` into Lang

SetStrings:
    if Lang is `it`
    begin
        put `Apri` into StrOpen
        put `Cerca` into StrFind
        put `Chiudi` into StrClose
        put `Salvato` into StrSaved
        put `Salvataggio fallito` into StrSaveFailed
        put `Ricaricato` into StrReloaded
        put `Modifica esterna rilevata` into StrExtChange
        put `Impossibile connettersi al server` into StrNoConnect
        put `Salva come (nome file senza .as):` into StrSaveAs
        put `(cartella vuota)` into StrEmpty
        put `.. (livello superiore)` into StrUpLevel
        put `/ (radice progetto)` into StrRoot
        put `L'editor è stato aggiornato. Riavviare?` into StrUpdated
        put `Riavvia il server manualmente.` into StrRestart
    end
    else if Lang is `fr`
    begin
        put `Ouvrir` into StrOpen
        put `Rechercher` into StrFind
        put `Fermer` into StrClose
        put `Enregistré` into StrSaved
        put `Échec de l'enregistrement` into StrSaveFailed
        put `Rechargé` into StrReloaded
        put `Modification externe détectée` into StrExtChange
        put `Impossible de se connecter au serveur` into StrNoConnect
        put `Enregistrer sous (nom de fichier sans .as) :` into StrSaveAs
        put `(dossier vide)` into StrEmpty
        put `.. (niveau supérieur)` into StrUpLevel
        put `/ (racine du projet)` into StrRoot
        put `L'éditeur a été mis à jour. Redémarrer ?` into StrUpdated
        put `Veuillez redémarrer le serveur manuellement.` into StrRestart
    end
    else if Lang is `de`
    begin
        put `Öffnen` into StrOpen
        put `Suchen` into StrFind
        put `Schließen` into StrClose
        put `Gespeichert` into StrSaved
        put `Speichern fehlgeschlagen` into StrSaveFailed
        put `Neu geladen` into StrReloaded
        put `Externe Änderung erkannt` into StrExtChange
        put `Verbindung zum Server nicht möglich` into StrNoConnect
        put `Speichern unter (Dateiname ohne .as):` into StrSaveAs
        put `(leerer Ordner)` into StrEmpty
        put `.. (Ebene höher)` into StrUpLevel
        put `/ (Projektstamm)` into StrRoot
        put `Der Editor wurde aktualisiert. Neu starten?` into StrUpdated
        put `Bitte den Server manuell neu starten.` into StrRestart
    end
    else
    begin
        put `Open` into StrOpen
        put `Find` into StrFind
        put `Close` into StrClose
        put `Saved` into StrSaved
        put `Save failed` into StrSaveFailed
        put `Reloaded` into StrReloaded
        put `External change detected` into StrExtChange
        put `Cannot connect to server` into StrNoConnect
        put `Save as (filename without .as):` into StrSaveAs
        put `(empty directory)` into StrEmpty
        put `.. (up one level)` into StrUpLevel
        put `/ (project root)` into StrRoot
        put `asedit has been updated. Restart to apply changes?` into StrUpdated
        put `Please restart the server manually.` into StrRestart
    end
    set the content of OpenBtn to StrOpen
    set the content of FindBtn to StrFind
    set the content of CloseBtn to StrClose
!! @hash 57698f27
!! @verified 57698f27
!!!
!! The editor checks on startup and periodically for updates to itself.
!! (explain)
!! then 
!   -- Check for updates --
    rest get VersionResult from `/version` or go VersionDone
    if VersionResult is `updated`
    begin
        if confirm StrUpdated
        begin
            rest get VersionResult from `/restart` or begin
                alert StrRestart
                go VersionDone
            end
            wait 3 seconds
            location the location

!			 Is this alternative valid?
!            rest get VersionResult from `/restart`
!            on failure alert StrRestart
!           	else
!            begin
!            	wait 3 seconds
!            	location the location
!            end
        end
    end
VersionDone:
!! @hash 96465c41
!! @verified 96465c41
!!!
!! Set up click handlers for the various editor functions.
!! Blocks-mode handlers (toggle, navigate, mark verified) live alongside
!! the existing flat-mode handlers. The pane editor textareas have
!! keyboard input handlers wired in EnterBlocks so we can stop watching
!! them when the pane is hidden.
!   -- Handlers --
    on click OpenBtn go to ShowBrowser
    on click PlusBtn go to NewFile
    on click FindBtn go to DoFind
    on click BlocksBtn go to ToggleBlocks
    on click BlocksPrev go to PrevBlock
    on click BlocksNext go to NextBlock
    on click BlocksVerify go to MarkVerified

    on pick BlocksDivider
    begin
        put the pick position into PickPos
        put property `x` of PickPos into PickX
        put the width of BlocksCodePane into CodeWidthAtPick
    end
    on drag
    begin
        put the drag position into DragPos
        put property `x` of DragPos into DragX
        put DragX into NewWidth
        take PickX from NewWidth
        add CodeWidthAtPick to NewWidth
        if NewWidth is less than 100 put 100 into NewWidth
        set style `flex` of BlocksCodePane to `0 0 ` cat NewWidth cat `px`
    end
    on drop
    begin
        put the width of BlocksCodePane into FinalWidth
        put FinalWidth into storage as `asedit-blocks-code-width`
    end

    put 0 into BlocksMode
    put 0 into BlockDirty
!! @hash ef9f0fc0
!! @verified d4e6253f
!!!
!! While editor is running it periodically saves changes made by the user
!! and updates the display to show updates made externally.
!! This avoids the need for any Save mechanism.
!   -- Start background loops --
    fork to AutoSave
    fork to PollFile
    stop
!! @hash f86feb98
!! @verified f86feb98
!!!
!! Every half-second, changes to the content are saved.
!!
!! TabSaved is an array of tab contents. If its content differs from that currently held in the editor, the current content is saved to the file and TabSaved is updated.
!   -- Auto-save loop --
AutoSave:
    wait 500 millis
    if TabCount is 0
    begin
        fork to AutoSave
        stop
    end
    codemirror get content of ContentEditor into Content
    index TabSaved to ActiveTab
    if Content is not TabSaved
    begin
        index TabPath to ActiveTab
        if TabPath is empty
        begin
            if Content is empty
            begin
                fork to AutoSave
                stop
            end
            put prompt StrSaveAs into File
            if File is empty
            begin
                fork to AutoSave
                stop
            end
            put File cat `.as` into File
            ! Save into the currently browsed directory
            if CurrentPath is not empty
                put CurrentPath cat `/` cat File into File
            index TabPath to ActiveTab
            put File into TabPath
            index TabName to ActiveTab
            put File into TabName
            gosub to RebuildTabBar
        end
        rest post Content to `/write/` cat TabPath or go SaveFailed
        index TabSaved to ActiveTab
        put Content into TabSaved
        set the content of StatusSpan to StrSaved
        fork to ClearStatus
    end
    fork to AutoSave
    stop

SaveFailed:
    set the content of StatusSpan to StrSaveFailed
    fork to ClearStatus
    fork to AutoSave
    stop
!! @hash a9c8ba92
!! @verified a9c8ba92
!!!
!! Every 3 seconds, the current file is re-read into FileContent.
!!
!! If this differs from what is currently held in TabSaved for this tab, the editor content is updated and a message is displayed briefly.
!   -- External change polling --
PollFile:
    wait 3 seconds
    if TabCount is 0
    begin
        fork to PollFile
        stop
    end
    ! In Blocks mode the in-memory Sections array is the source of truth;
    ! a silent reload would clobber the user's pane edits. Skip until they
    ! exit Blocks mode.
    if BlocksMode is 1 go to PollNext
    index TabPath to ActiveTab
    if TabPath is empty go to PollNext
    rest get FileContent from `/read/` cat TabPath or go PollNext
    codemirror get content of ContentEditor into Content
    index TabSaved to ActiveTab
    if FileContent is not TabSaved
    begin
        if Content is TabSaved
        begin
            ! Editor is clean -- silently reload
            put FileContent into TabSaved
            codemirror set content of ContentEditor to FileContent
            set the content of StatusSpan to StrReloaded
            fork to ClearStatus
        end
        else
        begin
            set the content of StatusSpan to StrExtChange
        end
    end
PollNext:
    fork to PollFile
    stop
!! @hash 528a0f6d
!! @verified 528a0f6d
!!!
!! (explain)
!   -- File browser with directory navigation --
ShowBrowser:
    rest get FileList from `/list/` cat CurrentPath or go BrowserError
    put the json count of FileList into FileCount
    set the elements of FileRow to FileCount
    set the elements of FileName to FileCount
    set the content of Scroller to ``

    ! Show current path at top
    create FileRow in Scroller
    set the style of FileRow to `padding:4px 8px;font-size:0.85em;color:#666;border-bottom:1px solid #ddd`
    if CurrentPath is empty
        set the content of FileRow to StrRoot
    else
        set the content of FileRow to `/` cat CurrentPath

    ! Show "back" row if inside a subdirectory
    if CurrentPath is not empty
    begin
        create FileRow in Scroller
        set the style of FileRow to `padding:4px 8px;cursor:pointer;background:#f0f0ff`
        set the content of FileRow to StrUpLevel
        on click FileRow go to GoUp
    end

    if FileCount is 0
    begin
        create FileRow in Scroller
        set the style of FileRow to `padding:4px 8px;color:#999`
        set the content of FileRow to StrEmpty
    end

    put 0 into N
    while N is less than FileCount
    begin
        put element N of FileList into Item
        put property `name` of Item into EntryName
        put property `type` of Item into EntryType
        index FileRow to N
        create FileRow in Scroller
        set the style of FileRow to `padding:3px 8px;cursor:pointer`
        index FileName to N
        create FileName in FileRow
        if EntryType is `dir`
        begin
            set the style of FileName to `display:block;padding:3px 0;cursor:pointer;font-weight:bold`
            set the content of FileName to `📁 ` cat EntryName
        end
        else
        begin
            set the style of FileName to `display:block;padding:3px 0;cursor:pointer`
            set the content of FileName to EntryName
        end
        on click FileName go to SelectEntry
        add 1 to N
    end
    on click CloseBtn go to CloseBrowser
    set style `display` of Overlay to `block`
    stop

GoUp:
    put the position of the last `/` in CurrentPath into N
    if N is less than 0
        put `` into CurrentPath
    else
        put left N of CurrentPath into CurrentPath
    go to ShowBrowser

BrowserError:
    set the content of StatusSpan to StrNoConnect
    fork to ClearStatus
    stop

!   -- Entry selected in browser --
SelectEntry:
    put the index of FileName into N
    put element N of FileList into Item
    put property `name` of Item into EntryName
    put property `type` of Item into EntryType
    if EntryType is `dir`
    begin
        ! Navigate into directory
        if CurrentPath is empty
            put EntryName into CurrentPath
        else
            put CurrentPath cat `/` cat EntryName into CurrentPath
        go to ShowBrowser
    end
    ! Build full relative path and open file
    if CurrentPath is empty
        put EntryName into TabItem
    else
        put CurrentPath cat `/` cat EntryName into TabItem
    set style `display` of Overlay to `none`
    put EntryName into File
    go to OpenFile

CloseBrowser:
    set style `display` of Overlay to `none`
    stop
!! @hash 90558828
!! @verified 90558828
!!!
!! This section is tab management; creating a new tab, opening a file, selecting a tab and closing a tab.
!   -- New empty tab --
NewFile:
    put TabCount into N
    add 1 to TabCount
    set the elements of TabPath to TabCount
    set the elements of TabName to TabCount
    set the elements of TabSaved to TabCount
    set the elements of TabBtn to TabCount
    set the elements of TabLabel to TabCount
    set the elements of TabClose to TabCount
    index TabPath to N
    put `` into TabPath
    index TabName to N
    put `new` into TabName
    index TabSaved to N
    put `` into TabSaved
    put N into ActiveTab
    go to ActivateTab

!   -- Open a file (TabItem=relative path, File=display name) --
OpenFile:
    ! Check if already open in a tab
    put 0 into N
    while N is less than TabCount
    begin
        index TabPath to N
        if TabPath is TabItem
        begin
            put N into ActiveTab
            go to ActivateTab
        end
        add 1 to N
    end
    ! Not open -- load from server and create a new tab
    rest get Content from `/read/` cat TabItem or go BrowserError
    add 1 to TabCount
    set the elements of TabPath to TabCount
    set the elements of TabName to TabCount
    set the elements of TabSaved to TabCount
    set the elements of TabBtn to TabCount
    set the elements of TabLabel to TabCount
    set the elements of TabClose to TabCount
    index TabPath to N
    put TabItem into TabPath
    index TabName to N
    put File into TabName
    index TabSaved to N
    put Content into TabSaved
    put N into ActiveTab
    go to ActivateTab

!   -- Switch to an existing tab --
SwitchTab:
    put the index of TabLabel into ActiveTab
    go to ActivateTab

!   -- Close a tab --
CloseTab:
    put the index of TabClose into M
    ! Shift elements above M down by one
    put M into N
    add 1 to N
    while N is less than TabCount
    begin
        index TabPath to N
        put TabPath into File
        subtract 1 from N
        index TabPath to N
        put File into TabPath
        add 1 to N
        index TabName to N
        put TabName into File
        subtract 1 from N
        index TabName to N
        put File into TabName
        add 1 to N
        index TabSaved to N
        put TabSaved into FileContent
        subtract 1 from N
        index TabSaved to N
        put FileContent into TabSaved
        add 1 to N
        add 1 to N
    end
    subtract 1 from TabCount
    if TabCount is 0
    begin
        put 0 into ActiveTab
        codemirror set content of ContentEditor to ``
        set the content of TabBar to ``
        stop
    end
    ! Adjust ActiveTab if it was after the closed tab
    if ActiveTab is greater than M subtract 1 from ActiveTab
    ! Clamp ActiveTab to valid range
    put TabCount into FileCount
    subtract 1 from FileCount
    if ActiveTab is greater than FileCount
    begin
        put FileCount into ActiveTab
    end
    go to ActivateTab

ActivateTab:
    index TabSaved to ActiveTab
    codemirror set content of ContentEditor to TabSaved
    gosub to RebuildTabBar
    stop
!! @hash 14377e61
!! @verified 14377e61
!!!
!! Rebuilding the tab bar is done by assigning styles to each tab to indicate which one is current.
RebuildTabBar:
!   -- Rebuild tab bar --
    set the content of TabBar to ``
    put 0 into N
    while N is less than TabCount
    begin
        index TabBtn to N
        create TabBtn in TabBar
        if N is ActiveTab
        begin
            set the style of TabBtn to `display:flex;align-items:center;gap:4px;padding:4px 10px;cursor:pointer;background:#555;color:white;border-bottom:2px solid lightgreen`
        end
        else
        begin
            set the style of TabBtn to `display:flex;align-items:center;gap:4px;padding:4px 10px;cursor:pointer;background:#3a3a3a;color:#aaa`
        end
        index TabLabel to N
        create TabLabel in TabBtn
        index TabName to N
        set the text of TabLabel to TabName
        on click TabLabel go to SwitchTab
        index TabClose to N
        create TabClose in TabBtn
        set attribute `src` of TabClose to `https://allspeak.ai/icon/stop.png`
        set the style of TabClose to `width:12px;height:12px;opacity:0.6;cursor:pointer`
        on click TabClose go to CloseTab
        add 1 to N
    end
    return
!! @hash 1347598c
!! @verified 1347598c
!!!
!! Here are some utility functions.
!   -- Find --
DoFind:
    codemirror find in ContentEditor
    stop

!   -- Utilities --
ClearStatus:
    wait 3 seconds
    set the content of StatusSpan to ``
    stop
!! @hash df75e3d8
!! @verified df75e3d8
!!!
!! Blocks parser. Walks the current Source line-by-line and populates the per-section arrays (Start, End, Prose, Code, Hash, Verified, HashState, VerifyState) plus the Outside-content array used to preserve text between sections during rebuild.
!!
!! Same classifier logic as tools/asdoc-check.as — the spec is one source of truth even though the code is duplicated here for the editor's in-process use.
ParseSource:
    put 0 into SecCount
    put 0 into InSection
    put `` into Source
    codemirror get content of ContentEditor into Source
    put Source into Lines
    split Lines
    put the elements of Lines into LineCount
    set the elements of Outside to 1
    index Outside to 0
    put `` into Outside
    put `` into OutsideTmp
    put 0 into N
    while N is less than LineCount
    begin
        index Lines to N
        put Lines into Line
        gosub to Classify
        if InSection is 0 gosub to OutsideDispatch
        else gosub to InsideDispatch
        add 1 to N
    end
    if InSection is 1
    begin
        ! Unclosed section — close synthetically so user can still see it.
        gosub to CloseSection
    end
    ! Save trailing outside chunk; need to grow Outside one past the last
    ! per-section index allocated by OpenSection.
    put SecCount into Tmp
    add 1 to Tmp
    set the elements of Outside to Tmp
    index Outside to SecCount
    put OutsideTmp into Outside
    return

OutsideDispatch:
    if Kind is `DOC` gosub to OpenSection
    else if Kind is `META` gosub to OpenSection
    else
    begin
        if OutsideTmp is empty put Line into OutsideTmp
        else put OutsideTmp cat newline cat Line into OutsideTmp
    end
    return

InsideDispatch:
    if Kind is `TERM` gosub to CloseSection
    else if Kind is `META` gosub to RecordMeta
    else if Kind is `DOC` gosub to AppendProse
    else if Kind is `CODE` gosub to AppendCode
    return

!   Classify the current line as code/comment or documentation
Classify:
    put `CODE` into Kind
    if Line is `!!!`
    begin
        put `TERM` into Kind
        return
    end
    if Line is `!!`
    begin
        put `DOC` into Kind
        put `` into LContent
        return
    end
    if Line starts with `!! ` or Line starts with `!!` cat tab
    begin
        put `DOC` into Kind
        put from 3 of Line into LContent
        gosub to MaybeMeta
        return
    end
    return

!   Deal with @ (META)
MaybeMeta:
    if LContent starts with `@`
    begin
        put `META` into Kind
        put from 1 of LContent into Tmp
        put the position of ` ` in Tmp into Pos
        if Pos is less than 0
        begin
            put Tmp into MetaKey
            put `` into MetaValue
        end
        else
        begin
            put left Pos of Tmp into MetaKey
            add 1 to Pos
            put from Pos of Tmp into MetaValue
        end
    end
    return

OpenSection:
    ! Finalize the outside chunk that ended with the previous line.
    put SecCount into Tmp
    add 1 to Tmp
    set the elements of Outside to Tmp
    index Outside to SecCount
    put OutsideTmp into Outside
    put `` into OutsideTmp
    put N into SecStartTmp
    add 1 to SecStartTmp
    put 1 into InSection
    put `` into SecProseTmp
    put `` into SecCodeTmp
    put `` into SecHashTmp
    put `` into SecVerifiedTmp
    put 0 into SecHasCode
    if Kind is `META` gosub to RecordMeta
    if Kind is `DOC` gosub to AppendProse
    return

RecordMeta:
    if MetaKey is `hash` put MetaValue into SecHashTmp
    if MetaKey is `verified` put MetaValue into SecVerifiedTmp
    return

AppendProse:
    if SecProseTmp is empty put LContent into SecProseTmp
    else put SecProseTmp cat newline cat LContent into SecProseTmp
    return

AppendCode:
    if SecCodeTmp is empty put Line into SecCodeTmp
    else put SecCodeTmp cat newline cat Line into SecCodeTmp
    if Line is not `` put 1 into SecHasCode
    return

CloseSection:
    ! Compute hash + states.
    if SecHasCode is 0 gosub to ScoreNoCode
    else gosub to ScoreWithCode
    ! Grow all the per-section arrays by one and store this section.
    put SecCount into I
    add 1 to SecCount
    set the elements of SecStart to SecCount
    set the elements of SecEnd to SecCount
    set the elements of SecProse to SecCount
    set the elements of SecCode to SecCount
    set the elements of SecHash to SecCount
    set the elements of SecVerified to SecCount
    set the elements of SecHashState to SecCount
    set the elements of SecVerifyState to SecCount
    index SecStart to I
    put SecStartTmp into SecStart
    index SecEnd to I
    put N into SecEnd
    add 1 to SecEnd
    index SecProse to I
    put SecProseTmp into SecProse
    index SecCode to I
    put SecCodeTmp into SecCode
    index SecHash to I
    put CurHash into SecHash    ! store current hash as the live one (not stale-stored)
    index SecVerified to I
    put SecVerifiedTmp into SecVerified
    index SecHashState to I
    put HashState into SecHashState
    index SecVerifyState to I
    put VerifyState into SecVerifyState
    put 0 into InSection
    put `` into OutsideTmp
    return

ScoreNoCode:
    put `` into CurHash
    put `no-code` into HashState
    if SecVerifiedTmp is empty put `unverified` into VerifyState
    else put `verified-no-code` into VerifyState
    return

ScoreWithCode:
    put hash SecCodeTmp into Tmp
    put left 8 of Tmp into CurHash
    if SecHashTmp is empty put `no-baseline` into HashState
    else if SecHashTmp is CurHash put `fresh` into HashState
    else put `stale` into HashState
    if SecVerifiedTmp is empty put `unverified` into VerifyState
    else if SecVerifiedTmp is CurHash put `verified-fresh` into VerifyState
    else put `verified-stale` into VerifyState
    return
!! @hash 56254133
!! @verified 56254133
!!!
!! Blocks view.
!! ToggleBlocks switches between flat and Blocks panes.
!! EnterBlocks parses the current source and shows block 0.
!! ExitBlocks flushes pending edits and reveals the flat pane again.
!! RenderBlock paints the textareas and the toolbar badge for the current section.
!! UpdateBadge derives badge text/colour from the section's hash and verify states.
ToggleBlocks:
    if BlocksMode is 0 go to EnterBlocks
    go to ExitBlocks

!   Enter Blocks mode
EnterBlocks:
    gosub to ParseSource
    if SecCount is 0
    begin
        set the content of StatusSpan to `No doc blocks in this file`
        fork to ClearStatus
        stop
    end
    put 0 into CurBlock
    put 1 into BlocksMode
    set style `display` of EditorArea to `none`
    set style `display` of BlocksArea to `flex`
    ! Restore divider position from previous session if persisted.
    get StoredWidth from storage as `asedit-blocks-code-width`
    if StoredWidth is `null` put 0 into StoredWidth
    if StoredWidth is `undefined` put 0 into StoredWidth
    if StoredWidth is empty put 0 into StoredWidth
    if StoredWidth is greater than 100
        set style `flex` of BlocksCodePane to `0 0 ` cat StoredWidth cat `px`
    gosub to RenderToc
    gosub to RenderBlock
    stop

!   Exit Blocks mode
ExitBlocks:
    gosub to FlushBlock
    put 0 into BlocksMode
    set style `display` of BlocksArea to `none`
    set style `display` of EditorArea to `block`
    stop

NextBlock:
    put SecCount into Tmp
    take 2 from Tmp
    if CurBlock is greater than Tmp stop
    gosub to FlushBlock
    add 1 to CurBlock
    gosub to RenderBlock
    stop

PrevBlock:
    if CurBlock is less than 1 stop
    gosub to FlushBlock
    take 1 from CurBlock
    gosub to RenderBlock
    stop

RenderBlock:
    index SecProse to CurBlock
    set the content of BlocksDocPane to SecProse
    index SecCode to CurBlock
    set the content of BlocksCodePane to SecCode
    gosub to UpdateBadge
    gosub to RenderToc
    return

UpdateBadge:
    put CurBlock into I
    add 1 to I
    set the content of BlocksTitle to `Block ` cat I cat ` of ` cat SecCount
    index SecVerifyState to CurBlock
    put SecVerifyState into VerifyState
    index SecHashState to CurBlock
    put SecHashState into HashState
    if VerifyState is `verified-fresh`
    begin
        set the content of BlocksBadge to `verified · fresh`
        set style `background` of BlocksBadge to `#2e7d32`
    end
    else if VerifyState is `verified-stale`
    begin
        set the content of BlocksBadge to `verified · stale`
        set style `background` of BlocksBadge to `#f9a825`
    end
    else if HashState is `no-code`
    begin
        set the content of BlocksBadge to `no code`
        set style `background` of BlocksBadge to `#666`
    end
    else
    begin
        set the content of BlocksBadge to `unverified`
        set style `background` of BlocksBadge to `#666`
    end
    return
!! @hash 47355e60
!! @verified b94f2261
!!!
!! Blocks save.
!! FlushBlock pushes the current pane edits back into the
!! per-section arrays (recomputing the section's hash if its code changed)
!! and rebuilds the full source by walking Outside + Section + Outside +
!! ... etc. The new source is written to ContentEditor (CodeMirror), which
!! the existing AutoSave loop persists to disk on its next iteration.
!! No-op if neither pane changed.
!!
FlushBlock:
    if BlocksMode is 0 return
    put the text of BlocksDocPane into NewProse
    put the text of BlocksCodePane into NewCode
    index SecProse to CurBlock
    put SecProse into OldProse
    index SecCode to CurBlock
    put SecCode into OldCode
    if NewProse is OldProse and NewCode is OldCode return
    index SecProse to CurBlock
    put NewProse into SecProse
    index SecCode to CurBlock
    put NewCode into SecCode
    ! Recompute hash and states for the edited block.
    put NewCode into SecCodeTmp
    put NewProse into SecProseTmp
    put 0 into SecHasCode
    if NewCode is not empty put 1 into SecHasCode
    index SecVerified to CurBlock
    put SecVerified into SecVerifiedTmp
    index SecHash to CurBlock
    put SecHash into SecHashTmp
    if SecHasCode is 0 gosub to ScoreNoCode
    else gosub to ScoreWithCode
    index SecHash to CurBlock
    put CurHash into SecHash
    index SecHashState to CurBlock
    put HashState into SecHashState
    index SecVerifyState to CurBlock
    put VerifyState into SecVerifyState
    gosub to RebuildSource
    codemirror set content of ContentEditor to Source
    gosub to UpdateBadge
    set the content of StatusSpan to `Block flushed`
    fork to ClearStatus
    return

RebuildSource:
    index Outside to 0
    put Outside into Source
    put 0 into I
    while I is less than SecCount
    begin
        gosub to BuildSectionText
        put Source cat BlkText into Source
        add 1 to I
        index Outside to I
        put Source cat newline cat Outside into Source
    end
    return

BuildSectionText:
    ! Reads I; writes BlkText with section I's reassembled lines.
    put `` into BlkText
    index SecProse to I
    put SecProse into Tmp
    if Tmp is not empty
    begin
        put Tmp into ProseSrc
        split ProseSrc
        put the elements of ProseSrc into PCount
        put 0 into PJ
        while PJ is less than PCount
        begin
            index ProseSrc to PJ
            put ProseSrc into PL
            if PL is empty put BlkText cat `!!` cat newline into BlkText
            else put BlkText cat `!! ` cat PL cat newline into BlkText
            add 1 to PJ
        end
    end
    index SecCode to I
    put SecCode into Tmp
    if Tmp is not empty put BlkText cat Tmp cat newline into BlkText
    index SecHash to I
    put SecHash into Tmp
    if Tmp is not empty put BlkText cat `!! @hash ` cat Tmp cat newline into BlkText
    index SecVerified to I
    put SecVerified into Tmp
    if Tmp is not empty put BlkText cat `!! @verified ` cat Tmp cat newline into BlkText
    put BlkText cat `!!!` into BlkText
    return
!! @hash d3dbcc0b
!! @verified d3dbcc0b
!!!
!! Mark verified — writes the current code's hash into the section's
!! "@verified" slot, then flushes so the file picks it up. The badge turns
!! green on the next render.
MarkVerified:
    if BlocksMode is 0 stop
    gosub to FlushBlock      ! ensure SecHash reflects current code first
    index SecHash to CurBlock
    put SecHash into SecHashTmp
    if SecHashTmp is empty stop    ! no-code section, nothing to verify
    index SecVerified to CurBlock
    put SecHashTmp into SecVerified
    put `verified-fresh` into Tmp
    index SecVerifyState to CurBlock
    put Tmp into SecVerifyState
    gosub to RebuildSource
    codemirror set content of ContentEditor to Source
    gosub to UpdateBadge
    set the content of StatusSpan to `Marked verified`
    fork to ClearStatus
    stop
!! @hash f2067b60
!! @verified f2067b60
!!!
!! Blocks TOC. Renders one row per parsed section in the BlocksToc
!! sidebar, highlighting the current block. Each row's label is the
!! first prose line of its section, truncated. Clicking a row flushes
!! any pending edit and jumps to that block.
RenderToc:
    set the content of BlocksToc to ``
    set the elements of TocRow to SecCount
    set the elements of TocLabel to SecCount
    put 0 into J
    while J is less than SecCount
    begin
        index TocRow to J
        create TocRow in BlocksToc
        if J is CurBlock set the style of TocRow to `padding:4px 10px;cursor:pointer;background:#1e88e5;color:white`
        else set the style of TocRow to `padding:4px 10px;cursor:pointer`
        index SecProse to J
        put SecProse into ProseSrc
        put the position of newline in ProseSrc into NL
        if NL is less than 0 put ProseSrc into FirstLine
        else put left NL of ProseSrc into FirstLine
        put J into Tmp
        add 1 to Tmp
        put Tmp cat `. ` cat FirstLine into FirstLine
        index TocLabel to J
        create TocLabel in TocRow
        set the content of TocLabel to FirstLine
        on click TocLabel go to JumpToBlock
        add 1 to J
    end
    return

JumpToBlock:
    put the index of TocLabel into Tmp
    if Tmp is CurBlock stop
    gosub to FlushBlock
    put Tmp into CurBlock
    gosub to RenderBlock
    stop
!! @hash ed01e660
!!!
