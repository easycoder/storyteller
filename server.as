!   server.as
!   AllSpeak development server.
!   Usage: allspeak server.as [-t|--tabs page1,page2,...] [port]    (default port: 8080)
!   Example: allspeak server.as -t edit,test 8080
!     opens edit.html and test.html in the default browser at localhost:8080
!
!   Serves two purposes:
!     1. Hosts the AllSpeak editor at localhost:<port>/edit.html
!     2. Serves project files at localhost:<port>/<project>.html
!        (replaces the need for python3 -m http.server)
!
!   API routes (paths are relative to the server's working directory):
!     GET  /list/<path>   →  returns JSON array of {name,type} entries in <path>
!     GET  /list          →  returns entries in the root directory
!     GET  /read/<file>   →  returns contents of <file>
!     POST /write/<file>  →  writes request body to <file>; returns OK
!     GET  /version       →  checks for updates from the repo; returns OK or updated
!     GET  /restart       →  restarts the server process
!     GET  /<file>        →  serves static files (HTML, JS, CSS, JSON, ECS)

    script CodeServer

    use server

    variable BaseDir
    variable FullPath
    variable FilePath
    variable Content
    variable FileList
    variable Port
    variable MimeType
    variable RepoBase
    variable RemoteVersion
    variable LocalVersion
    server Files

    put `https://allspeak.ai/code/` into RepoBase

    put cwd into BaseDir
    variable ArgCount
    variable ArgIndex
    variable CurrentArg
    variable TabList
    variable TabName
    variable TabIndex
    variable TabUrl
    put argc into ArgCount
    put `8080` into Port
    put empty into TabList
    put 0 into ArgIndex
    while ArgIndex is less than ArgCount
    begin
        put arg ArgIndex into CurrentArg
        if CurrentArg is `-t` or CurrentArg is `--tabs`
        begin
            increment ArgIndex
            if ArgIndex is less than ArgCount
                put arg ArgIndex into TabList
        end
        else
            put CurrentArg into Port
        increment ArgIndex
    end

    ! Ensure .code-version exists
    if file BaseDir cat `/.code-version` does not exist
    begin
        save `0` to BaseDir cat `/.code-version`
    end

    start Files on port Port

    print `AllSpeak dev server running on port ` cat Port
    print `Serving files from ` cat BaseDir
    print `Press Ctrl+C to stop`

    ! Check for updates at startup
    get RemoteVersion from url RepoBase cat `code-version` or begin
        print `Warning: could not check for updates`
    end
    if RemoteVersion is not empty
    begin
        replace ` ` with `` in RemoteVersion
        replace newline with `` in RemoteVersion
        load LocalVersion from BaseDir cat `/.code-version` or begin
            put `0` into LocalVersion
        end
        replace ` ` with `` in LocalVersion
        replace newline with `` in LocalVersion
        if RemoteVersion is not LocalVersion
        begin
            print `Updating from version ` cat LocalVersion cat ` to ` cat RemoteVersion
            download RepoBase cat `server.as` to BaseDir cat `/server.as`
            download RepoBase cat `asedit.json` to BaseDir cat `/asedit.json`
            download RepoBase cat `asedit.as` to BaseDir cat `/asedit.as`
            save RemoteVersion to BaseDir cat `/.code-version`
            print `Update complete`
        end
    end

    on Files request
    begin
        set FullPath to Files path

        if FullPath is `/version`
        begin
            get RemoteVersion from url RepoBase cat `code-version` or begin
                return `error` to Files with status 500
            end
            replace ` ` with `` in RemoteVersion
            replace newline with `` in RemoteVersion
            load LocalVersion from BaseDir cat `/.code-version` or begin
                put `0` into LocalVersion
            end
            replace ` ` with `` in LocalVersion
            replace newline with `` in LocalVersion
            if RemoteVersion is LocalVersion
                return `OK` to Files
            else
                return `updated` to Files
        end
        else if FullPath is `/restart`
        begin
            print `Restart requested`
            system background `sleep 2 && allspeak server.as ` cat Port
            return `OK` to Files
            exit
        end
        else if FullPath is `/list` or FullPath starts with `/list/`
        begin
            put FullPath into FilePath
            replace `/list` with `` in FilePath
            if left 1 of FilePath is `/` put from 1 of FilePath into FilePath
            if FilePath includes `..`
            begin
                return `Forbidden` to Files with status 403
            end
            if FilePath is empty
                set FileList to entries in BaseDir type `as,ecs,md,txt,json,html,css,js`
            else
                set FileList to entries in BaseDir cat `/` cat FilePath type `as,ecs,md,txt,json,html,css,js`
            return FileList to Files
        end
        else if FullPath starts with `/read/`
        begin
            put FullPath into FilePath
            replace `/read/` with `` in FilePath
            if FilePath includes `..`
            begin
                return `Forbidden` to Files with status 403
            end
            load Content from BaseDir cat `/` cat FilePath
            	on failure
            	begin
                	log `Could not open ` cat BaseDir cat  `/` cat FilePath
                    put empty into Content
                end
            return Content to Files
        end
        else if FullPath starts with `/write/`
        begin
            put FullPath into FilePath
            replace `/write/` with `` in FilePath
            if FilePath includes `..`
            begin
                return `Forbidden` to Files with status 403
            end
            get Content from Files
            save Content to BaseDir cat `/` cat FilePath
            return `OK` to Files
        end
        else
        begin
            ! Static file serving
            put from 1 of FullPath into FilePath
            if FilePath includes `..`
            begin
                return `Forbidden` to Files with status 403
            end
            if FilePath ends with `.html` put `text/html` into MimeType
            else if FilePath ends with `.json` put `application/json` into MimeType
            else if FilePath ends with `.as` put `text/plain` into MimeType
            else if FilePath ends with `.js` put `application/javascript` into MimeType
            else if FilePath ends with `.css` put `text/css` into MimeType
            else put `text/plain` into MimeType
            load Content from BaseDir cat `/` cat FilePath or begin
                ! Fall back to the AllSpeak CDN for /dist/* assets so that
                ! plugin loaders (e.g. `load showdown`, which requires
                ! /dist/vendor/showdown/showdown.min.js) succeed against the
                ! local dev server. AllSpeak's loader resolves relative paths
                ! against window.location.origin, not the runtime's origin.
                if FilePath starts with `dist/`
                begin
                    get Content from url `https://allspeak.ai/` cat FilePath or begin
                        return `Not found` to Files with status 404
                    end
                end
                else
                begin
                    return `Not found` to Files with status 404
                end
            end
            return Content to Files with type MimeType
        end
    end

    ! Open requested browser tabs (-t/--tabs flag) — done AFTER the
    ! request handler is registered so the tabs don't race the server
    ! and hit a 503 'Server handler not ready'.
    if TabList is not empty
    begin
        split TabList on `,`
        put 0 into TabIndex
        while TabIndex is less than the elements of TabList
        begin
            index TabList to TabIndex
            put TabList into TabName
            if TabName is not empty
            begin
                put `http://localhost:` cat Port cat `/` cat TabName cat `.html` into TabUrl
                print `Opening ` cat TabUrl
                browse TabUrl
            end
            increment TabIndex
        end
    end