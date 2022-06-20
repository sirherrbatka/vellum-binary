# vellum-binary
A custom, binary, file format for VELLUM library.

Uses cl-conspack, chipz, salza2.

Example

```
(vellum:copy-to :binary "~/path.vel" *dataframe* :compression :zlib)
(vellum:copy-to :binary "~/path.vel" *dataframe* :compression :gzip)
(vellum:copy-to :binary "~/path.vel" *dataframe*)
(defparameter *dataframe* (vellum:copy-from :binary "~/path.vel"))
```

Instead of file path you can also pass octet output-stream.

Provides WRITE-ELEMENTS-CALLBACK and READ-ELEMENTS-CALLBACK generic functions for programmer to implement custom serialization and deserialization for objects of a given type to streams. Type is taken from column-type. Implements handling for boolean, fixnum, single-float, double-float. Everything else is handled by cl-conspack library.

In addition to the built-in chipz/salza2 compression you can use compression algorithms of your choosing by specializing make-compressing-stream and make-decompressing-stream generic functions. It is probably preffered to use a quick compression, CL-ZSTD perhaps would be nice.

NOTE
Implementing WRITE-ELEMENTS-CALLBACK may result with files that cannot be read without loading additional READ-ELEMENTS-CALLBACK. Therefore it is adviced for you to abstain from doing so, unless needed.
