# rebol-httpd

This repository contains %httpd.reb, a single-file HTTP daemon for the Ren-C
branch of Rebol 3.

The emphasis of the daemon is (as with most Rebol code) to try and provide
features without relying on complex third-party libraries.  Hope is that it can
stay small, clear, and comprehensible enough to be modified by a layperson.

One notable use of this server is in the Android .APK build of Rebol.  It
provides a backchannel to hardware services for a second build of Rebol running
as WebAssembly in the browser:

https://github.com/metaeducation/rebol-server

## USAGE

For a simple server that just returns HTTP envelope with "Hello":

    import %httpd.reb
    wait srv: open [scheme: 'httpd 8000 [render "Hello"]]

Then point a browser at http://127.0.0.1:8000

## NOTES

R3-Alpha had a relatively incomplete model for network "PORT!s", which did not
undergo robust testing.  Advancing that code was not a priority of the Ren-C
initiative (which mostly focused on hammering out issues of the generic
design of the language).  Current effort is being focused on the WebAssembly
build of Rebol which inherits network abilities of its host--a browser or
Node.js--so advances on the custom Windows/Linux networking stacks are likely
to be slow in coming.

(For instance, while the Transport Layer Security code has been updated to
support TLS 1.2, it was only written and tested for reads.  The httpd server
hence cannot currently use it for writes to serve `https` links--that work
would have to be done by a "sufficiently motivated individual".)

## LICENSE

%httpd.reb is released under the Apache 2 License.

https://www.apache.org/licenses/LICENSE-2.0

* Copyright (c) 2017 Christopher Ross-Gill
* Copyright (c) 2017-2020 Rebol Open Source Contributors
