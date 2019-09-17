REBOL [
    Title: "Stress test for varying sizes of httpd payloads"
    Description: {
        This generates increasingly large strings to serve (doubling the length
        on each successive call).  The client checks to make sure the right
        number of bytes and the right contents come back.

        If `hangup` is specified as an argument to the script, then it will
        try to confuse the server by disconnecting from it every other time...
        and see if it can continue to serve data as expected despite that.
    }
]

import %../httpd.reb

if hangup?: did find system/options/args "hangup" [
    ;
    ; To get some variance in when a hangup occurs (early or late in a transfer)
    ; we randomize it.  We seed using the git commit, so that each new build will
    ; test new hangup points, while still being reproducible.
    ;
    either system/commit [
        print ["Seeding Hangup Randomization with Git Commit:" system/commit]
        random/seed system/commit 
    ][
        print "No system/commit--not seeding hangup randomization"
    ]
]


; http://www.fileformat.info/info/unicode/char/1f63a/index.htm
str: "HighCodepointCat(😺)"

n: 0

; CALL* does not wait for completion, so the server runs in the background
;
process-id: call* probe compose [
    (system/options/boot) "--do" (spaced [
        "import %../httpd.reb"
        "trap ["
            "str:" mold str "n:" n
            "wait srv: open [scheme: 'httpd 8000 ["
                "set 'n n + 1"
                "expected: copy str"
                "loop n [append expected expected]"
                "lib/print [{SERVER} n {:} (length of as binary! expected) {bytes}]"
                "render expected"
            "]]"
        "] then (func [e] [print mold e])"
    ])
]

quit: adapt 'lib/quit [
    call compose [{kill} {-9} (to text! process-id)]
]

; !!! What would the "legit" way to do this be?
;
print "Waiting for 3 seconds to ensure server starts up..."
wait 3

cycle [
    n: n + 1  ; at top so CONTINUE increments
    print newline

    expected: copy str
    loop n [append expected expected]
    total: length of as binary! expected

    partial: all [
        hangup?
        1 = random 2  ; Hang up 50% of the time
    ]
    then [
        ; If we need to hang up, we read at the raw TCP level vs. HTTP so we
        ; can pick how many bytes to read before closing.  But we are 
        ; going to be getting http headers with the data.  So we'll cut off
        ; the connection after some amount of the content bytes size...which
        ; won't ever cut off at the tail of the transmission (but close
        ; enough for being a pretty good test anyway).
        ;
        random total
    ]
    else [total]

    print [{CLIENT} n {: Will read} partial {/} total {bytes}]

    trap [
        if partial != total [
            port: open tcp://127.0.0.1:8000  ; raw TCP so we can hangup

            port/awake: function [e [event!]] [
                if e/type = 'read [
                    if partial != length of e/port/data [
                        print [
                           "READ with /PART of" partial "read wrong byte count:"
                           (length of e/port/data)
                        ]
                        quit 1
                    ]

                    print ["Client hanging up after only reading:" partial "bytes"]
                    close port  ; close with server data still pending
                    return true  ; and say "we handled it"
                ]
                return false  ; fall through to default AWAKE function
            ]
                
            open port  ; !!! Weird double-open (second is CONNECT)

            comment [  ; !!! This does not work, why not?
                while [not open? port] [wait port]
            ]
            wait 2  ; !!! Waiting for time seems to work (why?)

            ; We have to ask for data for the server to send anything.
            ; Use the bare minimum request.
            ; https://stackoverflow.com/q/6686261/
            ;
            write port unspaced [
                "GET / HTTP/1.1" cr lf
                "Host: 127.0.0.1" cr lf
                "Connection: close" cr lf
                cr lf
            ]
            data: read/part port partial

            ; The AWAKE handler will close the port
            while [open? port] [wait port]

            continue
        ] 

        === NORMAL READ ===
        ; expect success (this isn't testing server-side disconnects)

        data: read http://127.0.0.1:8000

        if (length of data) != total [
            print [
                "!! Bad response length;"
                    "expected" total
                    "but received" length of data
            ]
            quit 1
        ]

        actual: as text! data
    ] then (func [e] [
        print ["READ had an error:" mold e]
        quit 1
    ])
    
    if actual !== expected [
        print ["!! Bad response content bytes..."]
        quit 1
    ]

    print ["Client and Server exchanged:" total "bytes correctly"]

    if total > 20000000 [stop]  ; big enough?
]

quit 0  ; Note: Return code is heeded by Travis!
