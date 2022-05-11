(cl:defpackage #:vellum-binary
  (:use #:cl #:vellum.aux-package)
  (:export
   #:read-elements-callback
   #:write-elements-callback
   #:make-compressing-stream
   #:make-decompressing-stream))
