perl6uster::curl
====================================
## What

It's a small wrapper around LibCurl::Easy. Libcurl stores headers in a linked list, and repeated calls to LibCurl::Easy.set-header will keep adding to the end of the list. Dozens of duplicate headers can cause problems. Because I'm lazy, this stores all headers passed on the commandline in `%!hdr`, and calls to set-header do the following: 
* update `%!hdr`
* wipe libcurl's headers
* set new headers with the contents of %!hdr

## Methods
* method set-header(%header)
    * updates headers with the KV pairs in %header
* method set-header(Pair $p)
    * updates a single header
* method delete-header(Str $header)
    * deletes a user-supplied header
* method delete-header()
    * deletes all user-supplied headers

The following are forwarded to LibCurl::Easy:
* clear-header
* content
* error
* get-header
* getinfo
* perform
* primary-ip
* receiveheaders
* response-code
* setopt
* success
* version
* version-info

For anything else, use LibCurl::Easy directly through `$!easy`.
