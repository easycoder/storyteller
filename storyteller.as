!   Storyteller script — extended-markdown viewer that turns a folder of
!   .txt topics into a hyperlinked, themed browser app.

    script Storyteller

!! All DOM-element types and scratch variables used throughout the script.
!!
!! AllSpeak requires every variable to be declared before use, including loop counters. Grouping them here gives the reader the full surface in one place: typed DOM variables (divs, imgs, anchors, selects), the Showdown decorator callback, and the long list of scalars that subroutines reuse for state and arithmetic.

    div Body
    div Container
    div Content
    div TitleDiv
    div ButtonBar
    div TopicText
    div ImageDiv
    div Mask
    pre Resources
    img BigPic
    img TopImage
    img MidImage
    img BottomImage
    img HomeButton
    img BackButton
    img ForwardButton
    img InfoButton
    img Image
    a Link
    select Select
    option Option
    callback DecoratorCallback
    variable Mobile
    variable CDNPath
    variable Args
    variable Arg
    variable Mode
    variable NClicks
    variable Stories
    variable Themes
    variable Theme
    variable Layout
    variable BorderL
    variable BorderT
    variable BorderR
    variable BorderB
    variable BorderLeft
    variable BorderTop
    variable BorderRight
    variable BorderBottom
    variable AspectW
    variable AspectH
    variable SID
    variable TID
    variable CurrentSID
    variable CurrentTID
    variable Record
    variable C
    variable L
    variable N
    variable M
    variable P
    variable S
    variable Margin
    variable WindowWidth
    variable WindowHeight
    variable Width
    variable Height
    variable ButtonSize
    variable Title
    variable Payload
    variable Function
    variable Data
    variable Display
    variable Stid
    variable Attributes
    variable Source
    variable Style
    variable Class
    variable Classes
    variable Options
    variable List
    variable LinkCount
    variable SelectCount
    variable ImageCount
    variable Value
    variable DataID
    variable Prefix
    variable Topic
    variable Item
    variable Stack
    variable StackPointer
    variable FontScale
    variable FontSize
    variable Path
!! @hash 5fd519b4
!!!

!! Detect a phone in portrait mode; the layout branches on `Mobile` throughout.
!!
!! Landscape phones and desktops follow the same code path — only portrait phones get the simplified stacked layout without the framed parchment background.

    clear Mobile
    if mobile
    begin
    	if portrait set Mobile
    end
!! @hash 6ad0e50c
!!!

!! Pin the shared-asset CDN root to the upstream Storyteller GitHub repository on jsDelivr.
!!
!! Themes, icons, and any other framework assets are fetched from this base. Themes whose name begins with `/` opt out of the CDN and load from the local server instead (see SetupTheme).

    put `https://cdn.jsdelivr.net/gh/easycoder/storyteller@master` into CDNPath
!! @hash 687e2ea4
!!!

!! Discover the stories directory by reading the embedded `storyteller-stories` element in the host page.
!!
!! Letting the HTML pick the directory name lets one script serve different content bundles by changing one line of host markup. The wrapping slashes turn the bare name into a path fragment that can be safely concatenated.

    attach Resources to `storyteller-stories`
    put the content of Resources into Stories
    put `/` cat Stories cat `/` into Stories
!! @hash 95c623c6
!!!

!! Install global CSS rules into the document head before any topic renders.

    gosub to GetStyles
!! @hash 620c9ea3
!!!

!! Render the static layout from `storyteller.json` and attach every variable to its rendered element by id.
!!
!! Webson owns the structure now: container, the three parchment-frame background images, the content area, the title/button-bar/topic-text stack, and the four navigation buttons. From here the script only attaches and applies dynamic/responsive styles — it never builds DOM for static elements. On mobile the three frame images hide and the button-bar's flex `order` flips to put it above the title; Content is `display:flex; flex-direction:column` in Webson, so the CSS `order` swap is enough.

    attach Body to body
    clear Body
    rest get Layout from `storyteller.json`
    render Layout in Body

    attach Container to `container`
    attach MidImage to `mid-image`
    attach TopImage to `top-image`
    attach BottomImage to `bottom-image`
    attach Content to `content`
    attach TitleDiv to `title-div`
    attach ButtonBar to `button-bar`
    attach HomeButton to `home-button`
    attach BackButton to `back-button`
    attach ForwardButton to `forward-button`
    attach InfoButton to `info-button`
    attach TopicText to `topic-text`

    if Mobile
    begin
        set style `margin` of Container to `0.5em`
        set style `display` of MidImage to `none`
        set style `display` of TopImage to `none`
        set style `display` of BottomImage to `none`
        set style `order` of ButtonBar to `-1`
    end
    else
    begin
        set the style of Body to `overflow:hidden;width:100vw;height:100vh`
        set style `padding-right` of Container to `0.5em`
        on window resize gosub to SetStyles
    end
!! @hash f5297048
!!!

!! Hidden admin entry: triple-click the title to toggle `admin` mode.
!!
!! `Mode` is persisted to localStorage. A click while already in admin clears it immediately; three quick clicks while out of admin set it. There's no timer, so a stray slow click doesn't disarm the sequence — the counter just keeps incrementing until it lands on a multiple of three.

! Detect a triple click on the title
    get Mode from storage as `mode`
    put 0 into NClicks
    on click TitleDiv
    begin
        add 1 to NClicks
        if NClicks is 1
        begin
            if Mode is `admin`
            begin
                put empty into Mode
                put 0 into NClicks
            end
        end
        else if NClicks is 3
        begin
            put `admin` into Mode
            put 0 into NClicks
        end
    end
!! @hash 8465de1f
!!!

!! Parse the URL: honour `?arg=s=<dir>` (override stories directory) and `?arg=p=<sid>[/<tid>]` (deep-link to a page).
!!
!! Without overrides we pick up the last-viewed SID/TID from localStorage; first-time visitors land on `home/content`. The `history set url \`.\`` after a `p=` override cleans the query string from the address bar so a reload doesn't re-trigger it.

  	json parse url the location as Args
    put property `arg` of Args into Arg
    if Arg is empty
    begin
        get SID from storage as `id`
        if SID is empty put `home` into SID
        get TID from storage as `tid`
        if TID is empty put `content` into TID
    end
    else
    begin
        put property `arg` of Args into Arg
        if Arg is not empty
        begin
            put the position of `=` in Arg into N
            if N is not -1
            begin
                if left N of Arg is `s`
                begin
                    add 1 to N
                    put from N of Arg into Stories
                    put `/` cat Stories cat `/` into Stories
                end
                else if left N of Arg is `p`
                begin
                    add 1 to N
                    put from N of Arg into Item
                    put the position of `/` in Item into N
                    if N is greater than 0
                    begin
                        put left N of Item into SID
                        add 1 to N
                        put from N of Item into TID
                    end
                    else put Item into SID
                    history set url `.`
                end
            end
        end
    end
!! @hash bf28efa6
!!!

!! Set the browser tab title from the stories root.
!!
!! The empty `or begin end` swallows a missing `title.txt` silently — the page just keeps whatever title the host HTML already declared.

    rest get Title from Stories cat `title.txt?v=` cat now or begin end
    set the title to Title
!! @hash 691648b6
!!!

!! Run the deferred one-time setup: load the theme, build the buttons, compute responsive sizing.

    gosub to SetupTheme
    gosub to CreateButtons
    gosub to SetStyles
!! @hash a2ec4e75
!!!

!! Load Showdown and register the decorator callback that turns `~tag:data~` tokens into HTML.
!!
!! Showdown is the markdown→HTML engine. DecoratorCallback fires once per `~...~` token; the registered `Decorate` label dispatches to a per-tag ProcessXxx subroutine that rewrites the payload before Showdown splices it back into the output stream.

	load showdown
  	on DecoratorCallback go to Decorate
!! @hash c59be3a9
!!!

!! Initialise the navigation stack used by the back/forward buttons.

    put 0 into StackPointer
!! @hash 23cc7303
!!!

!! ViewRecord — fetch a record's content; on failure, fall back to `home/content`.
!!
!! This is the central jump target for any navigation: buttons, links, selects all eventually land here (directly or via ViewAnotherRecord). The `on failure` clause catches a missing record by routing the user back to home rather than leaving them on a blank page.

!	View a record, given its Subject and Topic ids.
ViewRecord:
    rest get Record from Stories cat SID cat `/content.txt?v=` cat now
    on failure begin
    	put `home` into SID
        put `content` into TID
    end
!! @hash 7180a581
!!!

!! Push the current location onto the back-button stack and reveal the back button if there's somewhere to return to.

! 	Add this topic to the stack
    put SID cat `/` cat TID into Stack
    if StackPointer is greater than 0 set style `display` of BackButton to `inline-block`
!! @hash f95cd7b6
!!!

!! Display the subject title, falling back to the SID itself when no `title.txt` exists.

!	Get the content
    set the style of TitleDiv to `text-align:center;font-size:1.6em;font-weight:bold`
    if Mobile set style `margin-top` of TitleDiv to `0.5em`
    rest get Title from Stories cat SID cat `/title.txt?v=` cat now on failure put empty into Title
    if Title is empty
    begin
    	put SID into Title
    end
    set the content of TitleDiv to Title
!! @hash 4490b11a
!!!

!! Fetch the topic text; if a specific topic is missing, fall back to the subject's `content` topic.

    rest get Topic from Stories cat SID cat `/` cat TID cat `.txt?v=` cat now
    on failure begin
    	put `content` into TID
        rest get Topic from Stories cat SID cat `/` cat TID cat `.txt?v=` cat now
    end
!! @hash e1dd198e
!!!

!! Persist the current location to localStorage so a reload returns to the same page.

!	Remember where we are
    put SID into storage as `id`
    put TID into storage as `tid`
    put SID into CurrentSID
    put TID into CurrentTID
!! @hash 8bbd4a86
!!!

!! Style the topic-text panel: mobile gets simple padding, desktop gets a scrollable height-constrained box.
!!
!! `calc(100% - 5em)` leaves room above for the button bar and title. `overflow-y:auto` gives the panel its own scrollbar so the page chrome stays fixed while the topic scrolls.

    if Mobile set the style of TopicText to `padding:0.5em`
    else set the style of TopicText to
    	`width:100%;height:calc(100% - 5em);background:none;overflow-y: auto`
            cat `;padding-right:1em`
!! @hash 059123cd
!!!

!! Convert the markdown topic to HTML via Showdown, with the Decorate callback rewriting `~...~` tokens to links, images, and selectors.
!!
!! The three counters are reset *before* the conversion because the callback bumps them per token; the next three sections then use those counts to wire up the rendered elements by ID.

!	Handle the links created by the showdown extension
    put 0 into LinkCount
    put 0 into ImageCount
    put 0 into SelectCount
    set the content of TopicText to showdown decode Topic with DecoratorCallback
!! @hash 06f729a1
!!!

!! Wire up every link the decorator emitted: attach by id, then route clicks by `data-id` prefix.
!!
!! Prefix → target: `S-<sid>` jumps to a subject's content topic, `T-<tid>` jumps within the current subject, `ST-<sid>/<tid>` jumps to a specific subject+topic, and the bare `theme` id opens an interactive theme-picker prompt. One shared handler reads the click target through the cursor model.

!	Process links
    set the elements of Link to LinkCount
    put 0 into N
    while N is less than LinkCount
    begin
        index Link to N
        attach Link to `ec-link-` cat N
        add 1 to N
    end
    on click Link
    begin
        put attribute `data-id` of Link into DataID
        if DataID is `theme`
        begin
        	rest get Themes from CDNPath cat `/themes/themes.txt?v=` cat now
            json split Themes on newline into Themes
            put `Here are the available themes:` cat newline into Item
            put 0 into N
            while N is less than the json count of Themes
            begin
            	if N is not 0 put Item cat `, ` into Item
            	put Item cat element N of Themes into Item
            	add 1 to N
            end
            put Item cat newline cat newline cat `You are currently using the '` cat Theme cat `' theme.` into Item
            put Item cat newline cat `Please type the name of the theme you want to use:` into Item
            put prompt Item into Item
            if Item is not empty
            begin
            	put Item into Theme
                put Theme into storage as `theme`
                gosub to SetupTheme
            end
        end
        else
        begin
          	put the position of `-` in DataID into N
            if N is greater than 0
            begin
              put left N of DataID into Prefix
              if Prefix is `S`
              begin
                  put from 2 of DataID into SID
                  put `content` into TID
                  go to ViewAnotherRecord
              end
              else if Prefix is `T`
              begin
                  put from 2 of DataID into TID
                  go to ViewAnotherRecord
              end
              else if Prefix is `ST`
              begin
                  put from 3 of DataID into TID
                  put the position of `/` in TID into N
                  if N is greater than 0
                  begin
                      put left N of TID into SID
                      add 1 to N
                      put from N of TID into TID
                      go to ViewAnotherRecord
                  end
              end
          end
      	end
    end
!! @hash 8ac0e926
!!!

!! Wire up images and provide a click-to-zoom modal overlay.
!!
!! Clicking an image (unless its `data-options` includes `nolink`) covers the page with a translucent mask hosting a 93vw/93vh copy of the image. Clicking either the mask or the big picture removes the overlay. `if true !Mobile` keeps the comment as a marker that the behaviour was once desktop-only.

!	Process images
    set the elements of ImageDiv to ImageCount
    set the elements of Image to ImageCount
    put 0 into N
    while N is less than ImageCount
    begin
        index ImageDiv to N
        index Image to N
        attach ImageDiv to `ec-imagediv-` cat N
        attach Image to `ec-image-` cat N
        add 1 to N
    end
    on click Image
    begin
        put attribute `data-options` of Image into Options
        if the position of `nolink` in Options is -1
        begin
        	if true !Mobile
            begin
                create Mask
                set the style of Mask to `position:fixed;top:0;left:0;width:100vw;height:150vh;`
                    cat `text-align:center;background-color:rgba(0,0,0,0.7)`
                create BigPic in Mask
                set the style of BigPic to
                    `max-width:93vw;max-height:93vh;margin-top:3%`
                put attribute `src` of Image into Source
                set attribute `src` of BigPic to Source
            end
            on click Mask remove element Mask
            on click BigPic remove element Mask
        end
    end
!! @hash e17335f3
!!!

!! Wire up every `<select>` the decorator emitted and route its onchange to navigation.
!!
!! Each select's `data-options` is a `|`-separated list of `<2-char-prefix><value>:<display>[!<extra-attrs>]` entries. Prefixes `S-`, `T-`, and `ST-` mirror the link prefixes; the optional `!` segment lets the markdown set arbitrary HTML attributes on the option (e.g. marking one as the default).

!	Process selectors
    set the elements of Select to SelectCount
    put 0 into N
    while N is less than SelectCount
    begin
    	index Select to N
    	attach Select to `ec-select-` cat N
        put attribute `data-options` of Select into Options
		json split Options on `|` into List
        put 0 into M
        while M is less than the json count of List
        begin
            create Option in Select
        	put element M of List into Value
            put Value into Display
            put the position of `:` in Value into P
            if P is not -1
            begin
            	put left P of Value into Value
                add 1 to P
                put from P of Display into Display
            end
            set attribute `data-st` of Option to left 2 of Value
            put from 2 of Value into Value
            put Display into Attributes
            put the position of `!` in Display into P
            if P is -1 put empty into Attributes
            else
            begin
            	put left P of Display into Display
                add 1 to P
                put from P of Attributes into Attributes
            end
            set the content of Option to Display
            if Attributes is not empty set the attributes of Option to Attributes
            set attribute `value` of Option to Value
        	add 1 to M
        end
    	add 1 to N
    end
    on change Select
    begin
        get Option from Select
        put attribute `data-st` of Option into Function
        put attribute `value` of Option into Value
        if Function is `S-`
        begin
	        put Value into SID
	        put `content` into TID
	        go to ViewAnotherRecord
        end
        else if Function is `T-`
        begin
	        put Value into TID
	        go to ViewAnotherRecord
        end
        else if Function is `ST-`
        begin
	        put Value into TID
            put the position of `/` in TID into N
            if N is greater than 0
            begin
	            put left N of TID into SID
	            add 1 to N
	            put from N of TID into TID
		        go to ViewAnotherRecord
            end
        end
    end
!! @hash 2cc2871c
!!!

!! Reset the scroll to the top of the newly rendered topic, then stop until the next click/navigation event.
!!
!! The 20-tick wait lets the browser finish laying out the rendered HTML before the scroll request, otherwise the scroll-to-zero races layout. Mobile scrolls the window; desktop scrolls the bounded TopicText panel.

    wait 20 ticks
    if Mode is `admin` alert `Scroll`
    if Mobile scroll to 0 else scroll TopicText to 0
!    scroll TopicText to 0 ! This doesn't work on mobile

 	stop
!! @hash 1326522a
!!!

!! SetupTheme — load the chosen theme's `theme.json` and apply its border/aspect/font settings.
!!
!! Themes live on the CDN by default (e.g. `pencil`); a theme name prefixed with `/` is read from the local server instead. The outer `or begin … end` clause recovers from a stale stored theme by clearing storage and falling back to the stories' default `theme.txt`. Mobile inflates the font scale 50% so the smaller viewport stays readable; desktop pulls the three parchment-frame images from the theme.

!	Set up the theme
SetupTheme:
	get Theme from storage as `theme`
    if Theme is empty rest get Theme from Stories cat  `theme.txt?v=` cat now
    if left 1 of Theme is `/`
    begin
        put from 1 of Theme into Theme
        put empty into Path
    end
    else put CDNPath into Path
    rest get Layout from Path cat `/themes/` cat Theme cat `/theme.json?v=` cat now
    or begin
    	put empty into storage as `theme`
    	rest get Theme from Stories cat  `theme.txt`
        if left 1 of Theme is `/`
        begin
            put from 1 of Theme into Theme
            put empty into Path
        end
        else put CDNPath into Path
    	rest get Layout from Path cat `/themes/` cat Theme cat `/theme.json?v=` cat now
    end
    put property `aspect-w` of Layout into AspectW
    put property `aspect-h` of Layout into AspectH
    put property `border-l` of Layout into BorderL
    put property `border-r` of Layout into BorderR
    put property `border-t` of Layout into BorderT
    put property `border-b` of Layout into BorderB
    put property `font-scale` of Layout into FontScale
    if Mobile
    begin
        multiply FontScale by 3
        divide FontScale by 2
    end
    else
    begin
	    set attribute `src` of MidImage to Path cat `/themes/` cat Theme cat `/mid.jpg`
	    set attribute `src` of TopImage to Path cat `/themes/` cat Theme cat `/top.jpg`
	    set attribute `src` of BottomImage to Path cat `/themes/` cat Theme cat `/bottom.jpg`
    end
	return
!! @hash 7e71bdc4
!!!

!! CreateButtons — wire each navigation button to its icon source and click handler; mobile/desktop differ only in the button-bar's padding/background.
!!
!! Back and Forward start hidden via Webson (`display:none`); Back appears once a record has been pushed onto the stack, Forward appears once Back has been used. Each handler rewrites SID/TID and jumps to ViewAnotherRecord, except Back/Forward themselves which call ViewRecord directly so they reuse the existing stack entry rather than pushing a new one.

!	Configure the buttons in the button-bar
CreateButtons:
    if Mobile
    begin
    	set style `padding` of ButtonBar to `0.25em`
        set style `background` of ButtonBar to `#eee`
    end
    else
    begin
    	set style `margin` of ButtonBar to `0 1em 0.5em 1em`
    end
    set attribute `src` of HomeButton to CDNPath cat `/icons/home.png`
    on click HomeButton
    begin
        put `home` into SID
        put `content` into TID
        go to ViewAnotherRecord
    end

    set attribute `src` of BackButton to CDNPath cat `/icons/arrow-back.png`
    on click BackButton
    begin
        put the elements of Stack into N
        take 1 from N
        take 1 from StackPointer
        index Stack to StackPointer
        put the position of `/` in Stack into N
        if N is -1 stop
        put left N of Stack into SID
        add 1 to N
        put from N of Stack into TID
        if StackPointer is 0 set style `display` of BackButton to `none`
        set style `display` of ForwardButton to `inline-block`
        go to ViewRecord
    end

    set attribute `src` of ForwardButton to CDNPath cat `/icons/arrow-forward.png`
    on click ForwardButton
    begin
        put the elements of Stack into N
        take 1 from N
        if N is StackPointer stop
        add 1 to StackPointer
        if StackPointer is N set style `display` of ForwardButton to `none`
        set style `display` of BackButton to `inline-block`
        index Stack to StackPointer
        put the position of `/` in Stack into N
        if N is -1 stop
        put left N of Stack into SID
        add 1 to N
        put from N of Stack into TID
        go to ViewRecord
    end

    set attribute `src` of InfoButton to CDNPath cat `/icons/info.png`
    on click InfoButton
    begin
        put `info` into SID
        put `content` into TID
        go to ViewAnotherRecord
    end
	return
!! @hash 29465003
!!!

!! ViewAnotherRecord — push a fresh location onto the stack before jumping to ViewRecord.
!!
!! Called from every link/select/non-back-forward button when the user navigates somewhere new. The early `stop` short-circuits redundant navigation to the same SID/TID. `VAR2` is the fall-through target after the same-page check; the slightly odd separate-label shape lets the same-page check exit cleanly via `stop`.

!	View another record, given the Subject and Topic ids
ViewAnotherRecord:
	if SID is not CurrentSID go to VAR2
    if TID is not CurrentTID go to VAR2
    stop
VAR2:
    add 1 to StackPointer
    add 1 to StackPointer giving N
    set the elements of Stack to N
    index Stack to StackPointer
    set style `display` of ForwardButton to `none`
    go to ViewRecord
!! @hash e7066b1a
!!!

!! SetStyles — compute the responsive layout: container, background images, buttons, content area, and font size.
!!
!! All sizes derive from the window height and the theme's `aspect-w`/`aspect-h`, so the parchment frame stays in proportion as the viewport changes. Borders are read from the theme as percentages and subtracted from the inner content area. The button row sizes to 1/20 of the content width; the font scales as content-height ÷ theme font-scale, with mobile boosted 5/4 for legibility. Called once at startup and again on every window-resize event.

!	Responsive design: Compute the size and position of all the screen elements
SetStyles:
    put the width of window into WindowWidth
    put the height of window into WindowHeight

!	Choose an optimum width based on the window height
	put WindowHeight into Height
	multiply Height by AspectW giving Width
    divide Width by AspectH

!	Make sure the window is wide enough
    take Width from WindowWidth giving Margin
    divide Margin by 2
    if Margin is less than 0
    begin
    	put 0 into Margin
        put WindowWidth into Width
    end

!	Style the Container
    set style `left` of Container to Margin cat `px`
    set style `top` of Container to 0
	set style `width` of Container to Width cat `px`
    set style `height` of Container to Height cat `px`

!	Style the background images
	if not Mobile
	begin
	    set the style of MidImage to `position:absolute;left:0;top:0;width:` cat Width
	    	cat `px;height:` cat `calc(` cat Height cat `px - 2vh)`
	    set the style of TopImage to `position:absolute;left:0;top:0;width:` cat Width cat `px`
	    set the style of BottomImage to `position:absolute;left:0;bottom:2vh;width:` cat Width cat `px`
    end

!	Calculate the borders
	if Mobile
    begin
    	put 0 into BorderLeft
    	put 0 into BorderRight
    	put 0 into BorderTop
    	put 0 into BorderBottom
    end
    else
    begin
	    multiply Width by BorderL giving BorderLeft
	    multiply Width by BorderR giving BorderRight
	    divide BorderLeft by 100
	    divide BorderRight by 100
	    take BorderLeft from Width
	    take BorderRight from Width

	    multiply Height by BorderT giving BorderTop
	    multiply Height by BorderB giving BorderBottom
	    divide BorderTop by 100
	    divide BorderBottom by 100
		take BorderTop from Height
	    take BorderBottom from Height
    end

    divide Width by 20 giving ButtonSize

!	Style the buttons
    if Mobile multiply ButtonSize by 2
    set style `width` of HomeButton to ButtonSize cat `px`
    set style `height` of HomeButton to ButtonSize cat `px`

    set style `height` of ButtonBar to ButtonSize cat `px`

	multiply ButtonSize by 3 giving M
    divide M by 2
    put M into N
    set style `left` of BackButton to `calc(` cat N cat `px + 0.25em)`
    set style `width` of BackButton to ButtonSize cat `px`
    set style `height` of BackButton to ButtonSize cat `px`

	add M to N
    set style `left` of ForwardButton to `calc(` cat N cat `px + 0.25em)`
    set style `width` of ForwardButton to ButtonSize cat `px`
    set style `height` of ForwardButton to ButtonSize cat `px`

    set style `width` of InfoButton to ButtonSize cat `px`
    set style `height` of InfoButton to ButtonSize cat `px`

!	Style the content
    set style `left` of Content to BorderLeft cat `px`
    set style `top` of Content to BorderTop cat `px`
    set style `width` of Content to Width cat `px`
    set style `height` of Content to Height cat `px`

!	Compute the font size
    divide Height by FontScale giving FontSize
    if Mobile
    begin
        multiply FontSize by 5
        divide FontSize by 4
        set style `line-height` of Container to `140%`
    end
    set style `font-size` of Container to FontSize cat `px`
    return
!! @hash a86cb398
!!!

!! Decorate — Showdown extension callback that rewrites each `~...~` token into HTML by dispatching to a per-tag subroutine.
!!
!! The token's payload (text between the tildes) is split on its first `:` into a tag and data. Tags: `sid`, `tid`, `stid`, `img`, `select`, `space`, `comment`, `theme`, `pn`, plus the no-colon standalone `clear`. The rewritten HTML is written back into the callback's payload slot, where Showdown picks it up to splice into the final document.

!------------------------------------------------------------------------------
!	This manages the Showdown extension.

!	Decorate is called for every occurrence of ~...~ in the topic data
Decorate:
    put the payload of DecoratorCallback into Payload
    put the position of `:` in Payload into N
    if N is -1
    begin
    	if Payload is `clear` gosub to ProcessClear
    end
    else
    begin
        put left N of Payload into Function
        add 1 to N
        put from N of Payload into Data
        if Function is `sid` gosub to ProcessSID
        else if Function is `tid` gosub to ProcessTID
        else if Function is `stid` gosub to ProcessSTID
        else if Function is `img` gosub to ProcessImage
        else if Function is `select` gosub to ProcessSelect
        else if Function is `space` gosub to ProcessSpace
        else if Function is `comment` gosub to ProcessComment
        else if Function is `theme` gosub to ProcessTheme
        else if Function is `pn` gosub to ProcessPreviousNext
    end
    set the payload of DecoratorCallback to Payload
    stop
!! @hash 8f770052
!!!

!! ProcessSID — emit a link that jumps to a new subject's `content` topic.

!	Process a request for a new subject
!   Syntax: ~sid:{sid}:{display text}~
ProcessSID:
	put Data into Display
    put the position of `:` in Data into N
    if N is not -1
    begin
	    put left N of Data into Data
	    add 1 to N
	    put from N of Display into Display
    end
    put `<a href="#" id="ec-link-` cat LinkCount cat `" class="button"`
    	cat ` data-id="S-` cat Data cat `">` cat Display cat `</a>` into Payload
    add 1 to LinkCount
    return
!! @hash 232e83fa
!!!

!! ProcessTID — emit a link that jumps to another topic within the current subject.

!	Process a request for a new topic
!   Syntax: ~tid:{tid}:{display text}~
ProcessTID:
	put Data into Display
    put the position of `:` in Data into N
    if N is not -1
    begin
	    put left N of Data into Data
	    add 1 to N
	    put from N of Display into Display
    end
    put `<a href="#" id="ec-link-` cat LinkCount cat `" class="button"`
    	cat ` data-id="T-` cat Data cat `">` cat Display cat `</a>` into Payload
    add 1 to LinkCount
    return
!! @hash cd98c022
!!!

!! ProcessSTID — emit a link that jumps to a specific topic in a specific subject (the `<sid>/<tid>` form).

!	Process a request for a new subject and topic
!   Syntax: ~stid:{stid}:{display text}~
ProcessSTID:
	put Data into Display
    put the position of `:` in Data into N
    if N is not -1
    begin
	    put left N of Data into Data
	    add 1 to N
	    put from N of Display into Display
    end
    put `<a href="#" id="ec-link-` cat LinkCount cat `" class="button"`
    	cat ` data-id="ST-` cat Data cat `">` cat Display cat `</a>` into Payload
    add 1 to LinkCount
    return
!! @hash c325a624
!!!

!! ProcessImage — embed an image with positioning classes, optional sizing, and a click-to-zoom anchor by default.
!!
!! Path resolution: `~img:<sid>/<file>:<styles>!<options>~` — if the path lacks a `/`, the current SID is used as the source. Style tokens recognised: `border`, `left`, `right`, `center`, `clear`, and `<n>%` (sets `width:<n>%` via inline style); anything else raises an alert. The optional `!<options>` segment can include `nolink` to suppress the zoom anchor.

!	Process an image, including positioning and class information
!   Syntax: ~img:{url}:{styles}!{options}~
ProcessImage:
	put empty into Options
	put the position of `/` in Data into N
    if N is -1 put SID into Source
    else
    begin
    	put left N of Data into Source
        add 1 to N
        put from N of Data into Data
    end
    put the position of `:` in Data into N
    put empty into Class
    if N is not -1
    begin
        put Source cat `/images/` cat left N of Data into Source
        add 1 to N
        if Data is not empty
        begin
! Redundant code removed, 27/7/21
!        	if Class is not empty put Class cat ` ` into Class
!        	put Class cat from N of Data into Class
        	put from N of Data into Class
        end
        put the position of `!` in Class into N
        if N is not -1
        begin
        	put Class into Options
            put left N of Class into Class
            add 1 to N
            put from N of Options into Options
        end
    end
    json split Class on ` ` into Classes
    put empty into Class
    put empty into Style
    put 0 into N
    while N is less than the json count of Classes
    begin
    	put empty into S
    	put element N of Classes into C
        if C is `border` begin end
        else if C is `left` begin end
        else if C is `right` begin end
        else if C is `center` begin end
        else if C is `clear` begin end
		else if right 1 of C is `%`
        begin
        	put the length of C into L
            take 1 from L
            put left L of C into S
            put `width:` cat S cat `%` into S
            put empty into C
        end
        else
        begin
        	alert `Unknown style ` cat C
            return
        end
        if C is not empty
        begin
	        if Class is not empty put Class cat ` ` into Class
	        put Class cat C into Class
        end
        if S is not empty
        begin
	        if Style is not empty put Style cat ` ` into Style
    	    put Style cat S into Style
        end
    	add 1 to N
    end
    put `<div id="ec-imagediv-` cat ImageCount into Payload
    if Class is not empty put Payload cat `" class="` cat Class into Payload
    if Style is not empty put Payload cat `" style="` cat Style into Payload
    put from 1 of Stories into Value
    if the position of `nolink` in Options is -1
    begin
        put Payload cat `">` cat `<a href="#">`
            cat `<img id="ec-image-` cat ImageCount cat `" src="` cat Value cat Source
            cat `" data-options="` cat Options cat `" style="width:100%" ></a></div>` into Payload
    end
    else
    begin
        put Payload cat `">` cat `<img id="ec-image-` cat ImageCount cat `" src="` cat Value cat Source
            cat `" data-options="` cat Options cat `" style="width:100%" ></div>` into Payload
    end
    add 1 to ImageCount
    return
!! @hash 4ec53225
!!!

!! ProcessClear — emit a `clear:both` divider so the next block sits below any floated images.

!	Process a 'clear'
!   Syntax: ~clear~
ProcessClear:
    put `<div style="height:1px;clear:both"></div>` into Payload
    return
!! @hash 96a028d9
!!!

!! ProcessSelect — emit a `<select>` placeholder; the selector-wiring loop above populates and binds it after rendering.

!	Process a 'select'
ProcessSelect:
    put `<select id="ec-select-` cat SelectCount cat `"`
    	cat ` data-options="` cat Data cat `"`
    	cat `></select>` into Payload
    add 1 to SelectCount
    return
!! @hash 1146f8cb
!!!

!! ProcessSpace — emit N non-breaking spaces on desktop, or a single `<br>` on mobile where horizontal padding is meaningless.

!	Process a space (add a non-breaking space)
!   Syntax: ~space~
ProcessSpace:
	if Mobile put `<br>` into Payload
    else
    begin
		put empty into Payload
		put the value of Data into M
	    put 0 into N
	    while N is less than M
	    begin
	    	put Payload cat `&nbsp;` into Payload
	        add 1 to N
	    end
    end
    return
!! @hash 8080da09
!!!

!! ProcessComment — drop the token from the rendered output, letting markdown carry in-source notes that never appear on screen.

!	Process a 'comment' (TODO)
!   Syntax: ~comment~
ProcessComment:
    put empty into Payload
    return
!! @hash d72b0739
!!!

!! ProcessTheme — emit a "change theme" link; clicking it triggers the prompt-based theme-picker handled in the link click handler above.

!	Process a 'theme'
!   Syntax: ~theme:{theme name}>~
ProcessTheme:
	put Data into Display
    put the position of `:` in Data into N
    if N is not -1
    begin
!	    put left N of Data into Data
	    add 1 to N
	    put from N of Display into Display
    end
    put `<a href="#" id="ec-link-` cat LinkCount cat `" class="button"`
    	cat ` data-id="theme">` cat Display cat `</a>` into Payload
    add 1 to LinkCount
    return
!! @hash c7eadbae
!!!

!! ProcessPreviousNext — render the Previous/Next pair at the foot of a topic, floated left and right with arrow icons.
!!
!! Either side can be empty (single direction). Each link uses a half-button-sized arrow icon from the CDN; a trailing `clear:both` div ensures subsequent content sits below the floats.

!	Process a Previous ... Next
!   Syntax: ~pn:{previous stid}:{display text}:{next stid}:{display text}~
ProcessPreviousNext:
    put empty into Payload
    divide ButtonSize by 2 giving S
    put the position of `:` in Data into N
    if N is not -1
    begin
        ! Get the stid
        put left N of Data into Stid
        add 1 to N
        put from N of Data into Data
        ! Check if there's a Next
        put the position of `:` in Data into M
        if M is -1
        begin
            put the length of Data into M
            put Data into Display
        end
        else
        begin
            put left M of Data into Display
            add 1 to M
        end
        put from M of Data into Data
        ! Do the Prev link
        if Stid is not empty
        begin
            put the position of `/` in Stid into P
            if P is  -1
                put `<a href="#" id="ec-link-` cat LinkCount
                    cat `" class="button" style="float:left"`
                    cat ` data-id="S-` cat Stid cat `">`
                    cat `<img src="` cat CDNPath cat `/icons/arrow-previous.png"`
                    cat ` style="width:` cat S cat `px;margin-right:1em">`
                    cat Display cat `</a>` into Payload
            else
                put `<a href="#" id="ec-link-` cat LinkCount
                    cat `" class="button" style="float:left"`
                    cat ` data-id="ST-` cat Stid cat `">`
                    cat `<img src="` cat CDNPath cat `/icons/arrow-previous.png"`
                    cat ` style="width:` cat S cat `px;margin-right:1em">`
                    cat Display cat `</a>` into Payload
            add 1 to LinkCount
        end
        ! Now the Next link
        put empty into Stid
        if Data is not empty
        begin
            put 0 into N
            put the position of `:` in Data into N
            if N is not -1
            begin
                ! Get the stid
                put left N of Data into Stid
                add 1 to N
                put from N of Data into Display
            end
            else
            begin
                put Data into Stid
                put Data into Display
            end
            if Stid is not empty
            begin
                put the position of `/` in Stid into P
                if P is  -1
                    put Payload cat  `<a href="#" id="ec-link-` cat LinkCount
                        cat `" class="button" style="float:right"`
                        cat ` data-id="S-` cat Stid cat `">` cat Display
                        cat `<img src="` cat CDNPath cat `/icons/arrow-next.png" style="width:` cat S cat `px;margin-left:1em">`
                        cat `</a>` into Payload
                else
                    put Payload cat `<a href="#" id="ec-link-`
                        cat LinkCount cat `" class="button" style="float:right"`
                        cat ` data-id="ST-` cat Stid cat `">` cat Display
                        cat `<img src="` cat CDNPath cat `/icons/arrow-next.png" style="width:` cat S cat `px;margin-left:1em">`
                        cat `</a>` into Payload
                add 1 to LinkCount
            end
        end
    end
    put Payload cat `<div style="clear:both;height:1"></div>` into Payload

    return
!! @hash 2550406c
!!!

!! GetStyles — install global CSS rules into the document head, called once at startup before any topic renders.
!!
!! Rules cover selector font-size, the `.clear`/`.border`/`.left`/`.right`/`.center` utility classes used by ProcessImage's class tokens, so the markdown can place and frame images without inline style.

!   Put some styles into the head
GetStyles:
!   Set the font size of all selectors
    set style `select` to `{font-size:1em}`
!   Force its owner to sit below all previous content
    set style `.clear` to `{clear:both}`
!   Image border and padding
    set style `.border` to `{padding:2px;border:1px solid black}`
!   Float left with a margin all round
    set style `.left` to `{float:left;margin:0.5em}`
!   Float right with a margin all round
    set style `.right` to `{float:right;margin:0.5em}`
!   Put the item in the centre of the page
    set style `.center` to `{margin:0 auto}`
    return
!! @hash c335a299
!!!
