REBOL [
    Title: "Stress test for varying sizes of httpd payloads"
    Description: {
        This generates increasingly large strings to serve (doubling the length
        on each successive call).  The client checks to make sure the right
        number of bytes and the right contents come back.
    }
]

import %../httpd.reb

; http://www.fileformat.info/info/unicode/char/1f63a/index.htm
str: "HighCodepointCat(😺)"

n: 1

; CALL* does not wait for completion, so the server runs in the background
;
process-id: call* probe compose [
    (system/options/boot) "--do" (spaced [
        "import %../httpd.reb"
        "trap ["
            "str:" mold str "n:" n
            "wait srv: open [scheme: 'httpd 8000 ["
                "expected: copy str"
                "loop n [append expected expected]"
                "lib/print [{SERVER} n {:} (length of as binary! expected) {bytes}]"
                "set 'n n + 1"
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
    expected: copy str
    loop n [append expected expected]
    print [{CLIENT} n {:} (length of as binary! expected) {bytes}]

    trap [
        data: read http://127.0.0.1:8000

        if (length of data) != (length of as binary! expected) [
            print [
                "!! Bad response length;"
                    "expected" length of as binary! expected
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

    print newline

    n: n + 1

    if (length of as binary! expected) > 20000000 [stop]  ; big enough?
]

quit 0  ; Note: Return code is heeded by Travis!
