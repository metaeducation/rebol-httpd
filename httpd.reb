Rebol [
    Title: "Web Server Scheme for Ren-C"
    Author: "Christopher Ross-Gill"
    Date: 13-Sep-2019
    File: %httpd.reb
    Home: https://github.com/rgchris/Scripts
    Version: 0.3.5
    Purpose: "An elementary Web Server scheme for creating fast prototypes"
    Rights: http://opensource.org/licenses/Apache-2.0
    Type: module
    Name: httpd
    History: [
        02-Feb-2019 0.3.5 "File argument for REDIRECT permits relative redirections"
        14-Dec-2018 0.3.4 "Add REFLECT handler (supports OPEN?); Redirect defaults to 303"
        16-Mar-2018 0.3.3 "Add COMPRESS? option"
        14-Mar-2018 0.3.2 "Closes connections (TODO: support Keep-Alive)"
        11-Mar-2018 0.3.1 "Reworked to support KILL?"
        23-Feb-2017 0.3.0 "Adapted from Rebol 2"
        06-Feb-2017 0.2.0 "Include HTTP Parser/Dispatcher"
        12-Jan-2017 0.1.0 "Original Version"
    ]
    Usage: {
        For a simple server that just returns HTTP envelope with "Hello":

            wait srv: open [scheme: 'httpd 8000 [render "Hello"]]

        Then point a browser at http://127.0.0.1:8000
    }
    Notes: {
        This has been transitionally changed to synchronous processing, as
        a step toward moving to a model more like goroutines:

        https://forum.rebol.info/t/1733
    }
]

net-utils: make object! [
;    net-log: func [return: [~] message [block! text!]] [
;        print message
;    ]

    net-log: :elide
]

; Previously WRITE was asynchronous and we can't catch errors via TRAP:
;
;   https://github.com/metaeducation/rebol-httpd/issues/4
;
; The new idea is that you can program -as if- things are synchronous...which
; is easy enough since currently they actually are.  But the idea is that the
; errors would be delivered to callsites as if they were as well.  Despite this
; being a relief to not have a different model for errors from everything else,
; there are still questions everything else has to answer:
;
;   https://forum.rebol.info/t/the-need-to-rethink-error/1371
;
trap-httpd: func [
    block [block!]
][
    return trap block then err -> [
        ;
        ; !!! We can now discern if it was the WRITE of the header or the WRITE
        ; of the content that failed...should errors be different?  How about
        ; for READ
        ;
        net-utils.net-log [
            "Response not sent to client.  Reason:" err.message
        ]

        ; Don't take down the server process on typical client disconnections.
        ;
        if not find [  ; !!! Should use ID codes, not strings!
            "Connection reset by peer"
            "Broken pipe"
            "operation canceled"  ; seen on READ
            "end of file"  ; seen on READ
        ] err.message [
            fail err
        ]
    ]
]

as-text: func [
    {Variant of AS TEXT! that scrubs out invalid UTF-8 sequences}
    return: [text!]
    binary [binary!]
    <local> mark
][
    mark: binary
    while [mark: invalid-utf8? mark] [
        mark: change/part mark #{EFBFBD} 1
    ]
    return to text! binary
]

sys.util.make-scheme [
    title: "HTTP Server"
    name: 'httpd

    spec: make system.standard.port-spec-head [port-id: actions: _]

    init: func [return: [~] server [port!]] [
        let spec: server.spec
        probe mold spec

        any [
            url? spec.ref
            block? spec.actions
            ok? parse spec.ref [
                set-word! &lit-word?
                spec.port-id: integer!, spec.actions: *in* block!
            ]
            fail "Server lacking core features."
        ]

        server.locals: make object! [
            handler: ~
            subport: ~
            open?: ~
            clients: make block! 1024
        ]

        server.locals.handler: func [
            return: [~]
            request [object!]
            response [object!]
        ] compose [
            apply func [request response render redirect print] (
                match block! server.spec.actions else [default-response]
            )[
                request response
                :response.render :response.redirect :response.print
            ]
        ]

        server.locals.subport: make port! [scheme: 'tcp]

        server.locals.subport.spec.port-id: spec.port-id

        server.locals.subport.locals: make object! [
            instance: 0
            request: null
            response: null
            parent: :server
        ]

        server.locals.subport.spec.accept: func [
            return: [~]
            client [port!]
        ][
            net-utils.net-log unspaced [
                "Accepting Connection [" client.locals.instance: me + 1 "]"
            ]

            cycle [
                ;
                ; It is possible that while we are reading that the client
                ; could hang up.  For such errors that are common, just close
                ; the port.
                ;
                trap-httpd [
                    read client
                ] then [
                    stop
                ]

                case [
                    not client.locals.parent.locals.open? [
                        stop
                    ]

                    ; @gchiu's copy of httpd had handling for null client.data
                    ; (hence the `maybe` on the find of client.data)  This
                    ; should probably not be possible, so assert...but put
                    ; in the changes just in case.
                    ;
                    assert [not null? client.data, binary? client.data]

                    find maybe client.data #{0D0A0D0A} [
                        transcribe client
                        dispatch client
                        stop
                    ]

                    true [stop]  ; from @gchiu's copy
                ]
            ]

            net-utils.net-log unspaced [
                "Closing Connection [" client.locals.instance "]"
            ]

            close client
        ]
    ]

    actor: [
        open: func [server [port!]] [
            net-utils.net-log ["Server running on port id" server.spec.port-id]
            open server.locals.subport
            server.locals.open?: yes
            return server
        ]

        reflect: func [server [port!] property [word!]][
            switch property [
                'open? [
                    return server.locals.open?
                ]

                fail [
                    "HTTPd port does not reflect this property:"
                        uppercase mold property
                ]
            ]
        ]

        close: func [server [port!]] [
            server.locals.open?: no
            close server.locals.subport
            return server
        ]
    ]

    default-response: [probe request.action]

    request-prototype: make object! [
        raw: null
        version: 1.1
        method: "GET"
        action: null
        headers: null
        http-headers: null
        oauth: null
        target: null
        binary: null
        content: null
        length: null
        timeout: null
        type: 'application/x-www-form-urlencoded
        server-software: unspaced [
            "Rebol/" system.product space "v" system.version
        ]
        server-name: null
        gateway-interface: null
        server-protocol: "http"
        server-port: null
        request-method: null
        request-uri: null
        path-info: null
        path-translated: null
        script-name: null
        query-string: null
        remote-host: null
        remote-addr: null
        auth-type: null
        remote-user: null
        remote-ident: null
        content-type: null
        content-length: null
        error: null
    ]

    response-prototype: make object! [
        status: 404
        content: "Not Found"
        location: null
        type: "text/html"
        length: 0
        kill?: false
        close?: true
        compress?: false

        render: meth [response [text! binary!]] [
            status: 200
            content: response
        ]

        print: meth [response [text!]] [
            status: 200
            content: response
            type: "text/plain"
        ]

        redirect: meth [target [url! file!] /code [integer!]] [
            status: code: default [303]
            content: "Redirecting..."
            type: "text/plain"
            location: target
        ]
    ]

    transcribe: func [
        return: [~]
        client [port!]

      <static>

        request-action (["HEAD" | "GET" | "POST" | "PUT" | "DELETE"])

        request-path (use [chars] [
            chars: complement charset [#"^@" - #" " #"?"]
            [some chars]
        ])

        request-query (use [chars] [
            chars: complement charset [#"^@" - #" "]
            [try some chars]  ; (empty requests are legal)
        ])

        header-feed ([newline | cr lf])

        header-part (use [chars] [
            chars: complement charset [#"^(00)" - #"^(1F)"]
            [some chars, try some [header-feed some " " some chars]]
        ])

        header-name (use [chars] [
            chars: charset ["_-0123456789" #"a" - #"z" #"A" - #"Z"]
            [some chars]
        ])

        spaces-or-tabs (use [chars] [
            chars: charset " ^-"
            [some chars]
        ])

        header-prototype (make object! [
            Accept: "*/*"
            Connection: "close"
            User-Agent: null
            Content-Length: null
            Content-Type: null
            Authorization: null
            Range: null
            Referer: null
        ])
    ][
        client.locals.request: make request-prototype [
            parse raw: client.data [
                method: across request-action, space
                request-uri: across [
                    target: across request-path, try [
                        "?", query-string: across request-query
                    ]
                ]
                spaces-or-tabs
                "HTTP/" version: across ["1.0" | "1.1"]
                header-feed
                (headers: make block! 10)
                some [
                    name: across header-name, ":", try some " "
                    value: across header-part, header-feed
                    (
                        name: as-text name
                        value: as-text value
                        append headers spread reduce [to set-word! name value]
                        switch name [
                            "Content-Type" [content-type: value]
                            "Content-Length" [length: content-length: value]
                        ]
                    )
                ]
                header-feed, content: <here>, to <end> (
                    binary: copy :content
                    content: does [content: as-text binary]
                )
            ] except [
                net-utils.net-log error: "Could Not Parse Request"
                return
            ]

            version: to text! :version
            request-method: method: to text! :method
            path-info: target: as-text :target
            action: spaced [method target]
            request-uri: as-text request-uri
            server-port: select (maybe query client) 'local-port
            remote-addr: select (maybe query client) 'remote-ip

            headers: make header-prototype
                http-headers: new-line/skip headers true 2

            type: all [
                text? type: headers.Content-Type
                copy/part type find type ";"   ; FIND revokes /PART when null
            ] else ["text/html"]

            length: content-length: attempt [  ; !!! Can LENGTH be non-integer?
                to integer! maybe length
            ] else [0]

            net-utils.net-log action
        ]
    ]

    dispatch: func [
        return: [~]
        client [port!]

      <static>

        status-codes ([
            200 "OK"
            201 "Created"
            204 "No Content"

            301 "Moved Permanently"
            302 "Moved temporarily"
            303 "See Other"
            307 "Temporary Redirect"

            400 "Bad Request"
            401 "No Authorization"
            403 "Forbidden"
            404 "Not Found"
            411 "Length Required"

            500 "Internal Server Error"
            503 "Service Unavailable"
        ])

        build-header (func [response [object!]] [
            return append make binary! 1024 spaced inside [] collect [
                if not find status-codes response.status [
                    response.status: 500
                ]
                any [
                    not match [binary! text!] response.content
                    empty? response.content
                ] then [
                    response.content: " "
                ]

                keep spread ["HTTP/1.1" response.status
                    select status-codes response.status]
                keep spread [cr lf "Content-Type:" response.type]
                keep spread [cr lf "Content-Length:"
                    length of as binary! response.content  ; bytes (not chars)
                ]
                if response.compress? [
                    keep spread [cr lf "Content-Encoding:" "gzip"]
                ]
                if response.location [
                    keep spread [cr lf "Location:" response.location]
                ]
                if response.close? [
                    keep spread [cr lf "Connection:" "close"]
                ]
                keep spread [cr lf "Cache-Control:" "no-cache"]
                keep spread [cr lf "Access-Control-Allow-Origin: *"]
                keep spread [cr lf cr lf]
            ]
        ])
    ][
        let response: client.locals.response: make response-prototype []

        if object? client.locals.request [
            client.locals.parent.locals.handler client.locals.request response
        ] else [  ; don't crash on bad request
            response.status: 500
            response.type: "text/html"
            response.content: "Bad request."
        ]

        if response.compress? [
            response.content: gzip response.content
        ]

        trap-httpd [  ; don't crash server if client disconnects while we write
            write client hdr: build-header response
            write client response.content
        ]
    ]
]
