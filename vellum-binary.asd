(asdf:defsystem #:vellum-binary
  :name "vellum-binary"
  :description "vellum custom binary format."
  :version "1.2.1"
  :license "BSD simplified"
  :author "Marek Kochanowicz"
  :depends-on ((:version #:vellum ((>= "1.3.0")))
               #:chipz
               #:salza2
               #:trivial-utf-8
               #:nibbles
               #:ieee-floats
               #:cl-conspack)
  :serial T
  :pathname "source"
  :components ((:file "package")
               (:file "code")))
