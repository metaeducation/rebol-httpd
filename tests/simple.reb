import %../httpd.reb

; http://www.fileformat.info/info/unicode/char/1f63a/index.htm
expected: "HighCodepointCat(😺)"

; CALL* does not wait for completion, so the server runs in the background
;
process-id: call* probe compose [
    (system/options/boot) "--do" (unspaced [
        "import %../httpd.reb" space
        "trap ["
            "wait srv: open [scheme: 'httpd 8000 [render {" expected "}]]"
        "] then (func [e] [print mold e])"
    ])
]

quit: adapt :lib/quit [
    call compose [{kill} {-9} (to text! process-id)]
]

; !!! What would the "legit" way to do this be?
;
print "Waiting for 3 seconds to ensure server starts up..."
wait 3

trap [
    actual: as text! read http://127.0.0.1:8000
] then (func [e] [
    print ["READ had an error:" mold e]
    quit 1
])

print ["Server responded with:" mold actual]

if actual !== expected [
    print ["Bad response, expected:" mold expected]
    quit 1
]

quit 0  ; return code is heeded by Travis 
