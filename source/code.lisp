(cl:in-package #:vellum-binary)


(define-constant +version+ 0)


(defun read-file-header (stream)
  (unless (and (eql (read-byte stream) #x66)
               (eql (read-byte stream) #x76) ; v
               (eql (read-byte stream) #x65) ; e
               (eql (read-byte stream) #x6C) ; l
               (eql (read-byte stream) #x6C) ; l
               (eql (read-byte stream) #x75) ; u
               (eql (read-byte stream) #x6D)); m
    (error "Not a Vellum binary file!"))
  (let ((version (nibbles:read-ub16/be stream)))
    (when (> version +version+)
      (error "File generated by newer version of VELLUM-BINARY."))
    (when (< version +version+)
      (error "File generated by older version of VELLUM-BINARY."))))


(defun write-file-header (stream)
  (write-byte #x66 stream)
  (write-byte #x76 stream) ; v
  (write-byte #x65 stream) ; e
  (write-byte #x6C stream) ; l
  (write-byte #x6C stream) ; l
  (write-byte #x75 stream) ; u
  (write-byte #x6D stream) ; m
  (nibbles:write-ub16/be +version+ stream) ; version
  )


(defgeneric make-decompressing-stream (symbol input-stream))
(defgeneric make-compressing-stream (symbol output-stream))


(defmethod make-compressing-stream ((symbol (eql nil))
                                    output-stream)
  output-stream)


(defmethod make-compressing-stream ((symbol (eql :zlib))
                                    output-stream)
  (salza2:make-compressing-stream 'salza2:zlib-compressor
                                  output-stream))


(defmethod make-compressing-stream ((symbol (eql :gzip))
                                    output-stream)
  (salza2:make-compressing-stream 'salza2:gzip-compressor
                                  output-stream))


(defmethod make-decompressing-stream ((symbol (eql nil))
                                      input-stream)
  input-stream)


(defmethod make-decompressing-stream ((symbol (eql :zlib))
                                      input-stream)
  (chipz:make-decompressing-stream :zlib input-stream))


(defmethod make-decompressing-stream ((symbol (eql :gzip))
                                      input-stream)
  (chipz:make-decompressing-stream :gzip input-stream))


(defun read-object (stream)
  (conspack:decode-stream stream))


(defun write-object (object stream)
  (conspack:encode object :stream stream))


(defgeneric read-elements-callback (column-type))
(defgeneric write-elements-callback (column-type))


(declaim (inline mask-signed))
(defun mask-signed (x size)
  (declare (type fixnum x) (type (unsigned-byte 8) size))
  (logior x (- (mask-field (byte 1 (1- size)) x))))


(defmethod read-elements-callback (column-type)
  (cond ((subtypep column-type '(unsigned-byte 8))
         (lambda (stream) (read-byte stream)))
        ((subtypep column-type '(unsigned-byte 16))
         (lambda (stream) (nibbles:read-ub16/be stream)))
        ((subtypep column-type '(unsigned-byte 32))
         (lambda (stream) (nibbles:read-ub32/be stream)))
        ((subtypep column-type '(unsigned-byte 64))
         (lambda (stream) (nibbles:read-ub64/be stream)))
        ((subtypep column-type '(signed-byte 8))
         (lambda (stream) (mask-signed (read-byte stream) 8)))
        ((subtypep column-type '(signed-byte 16))
         (lambda (stream) (nibbles:read-sb16/be stream)))
        ((subtypep column-type '(signed-byte 32))
         (lambda (stream) (nibbles:read-sb32/be stream)))
        ((subtypep column-type '(signed-byte 64))
         (lambda (stream) (nibbles:read-sb64/be stream)))
        ((subtypep column-type 'short-float)
         (lambda (stream) (coerce (nibbles:read-ieee-single/be stream) 'short-float)))
        ((subtypep column-type 'single-float)
         (lambda (stream) (nibbles:read-ieee-single/be stream)))
        ((subtypep column-type 'double-float)
         (lambda (stream) (nibbles:read-ieee-single/be stream)))
        (t (lambda (stream) (read-object stream)))))


(defmethod write-elements-callback (column-type)
  (cond ((subtypep column-type '(unsigned-byte 8))
         (lambda (object stream) (write-byte object stream)))
        ((subtypep column-type '(unsigned-byte 16))
         (lambda (object stream) (nibbles:write-ub16/be object stream)))
        ((subtypep column-type '(unsigned-byte 32))
         (lambda (object stream) (nibbles:write-ub32/be object stream)))
        ((subtypep column-type '(unsigned-byte 64))
         (lambda (object stream) (nibbles:write-ub64/be object stream)))
        ((subtypep column-type '(signed-byte 8))
         (lambda (object stream) (write-byte (logand #b11111111 object) stream)))
        ((subtypep column-type '(signed-byte 16))
         (lambda (object stream) (nibbles:write-sb16/be object stream)))
        ((subtypep column-type '(signed-byte 32))
         (lambda (object stream) (nibbles:write-sb32/be object stream)))
        ((subtypep column-type '(signed-byte 64))
         (lambda (object stream) (nibbles:write-sb64/be object stream)))
        ((subtypep column-type 'short-float)
         (lambda (object stream) (nibbles:write-ieee-single/be (coerce object 'single-float) stream)))
        ((subtypep column-type 'single-float)
         (lambda (object stream) (nibbles:write-ieee-single/be object stream)))
        ((subtypep column-type 'double-float)
         (lambda (object stream) (nibbles:write-ieee-single/be object stream)))
        (t (lambda (object stream) (write-object object stream)))))


(defmethod read-elements-callback ((column-type (eql 'fixnum)))
  (lambda (stream) (nibbles:read-sb64/be stream)))


(defmethod write-elements-callback ((column-type (eql 'fixnum)))
  (lambda (object stream) (nibbles:write-sb64/be object stream)))


(defmethod write-elements-callback ((column-type (eql 'boolean)))
  (lambda (object stream) (write-byte (if object 1 0) stream)))


(defmethod read-elements-callback ((column-type (eql 'boolean)))
  (lambda (stream) (= (read-byte stream) 1)))


(defun restore-column (column-type column stream)
  (let ((elements-callback (read-elements-callback column-type)))
    (ensure-function elements-callback)
    (cl-ds.common.rrb:sparse-rrb-tree-map
     (cl-ds.dicts.srrb:access-tree column)
     (cl-ds.dicts.srrb:access-shift column)
     :leaf-function (lambda (node)
                      (iterate
                        (declare (type fixnum i)
                                 (optimize (speed 3)))
                        (with content = (cl-ds.common.rrb:sparse-rrb-node-content node))
                        (for i from 0 below (cl-ds.common.rrb:sparse-rrb-node-size node))
                        (setf (aref content i) (funcall elements-callback stream))))))
  column)


(defun restore-bitmasks (column stream shift nodes-count)
  (declare (type fixnum nodes-count shift)
           (optimize (speed 3)))
  (let ((tag (cl-ds.common.abstract:read-ownership-tag column))
        (type (cl-ds.dicts.srrb:read-element-type column))
        (i 0))
    (declare (type fixnum i))
    (setf (cl-ds.dicts.srrb:access-tree column) (cl-ds.common.rrb:make-sparse-rrb-node
                                                 :ownership-tag tag))
    (cl-ds.common.rrb:sparse-rrb-tree-map
     (cl-ds.dicts.srrb:access-tree column)
     shift
     :tree-function
     (lambda (node)
       (incf i)
       (let* ((bitmask (nibbles:read-ub32/be stream)))
         (setf (cl-ds.common.rrb:sparse-rrb-node-bitmask node) bitmask
               (cl-ds.common.rrb:sparse-rrb-node-content node) (map-into (make-array (logcount bitmask))
                                                                         (lambda ()
                                                                           (cl-ds.common.rrb:make-sparse-rrb-node
                                                                            :ownership-tag tag)))))
       (when (> i nodes-count)
         (return-from restore-bitmasks nil)))
     :leaf-function
     (lambda (node)
       (incf i)
       (let* ((bitmask (nibbles:read-ub32/be stream)))
         (setf (cl-ds.common.rrb:sparse-rrb-node-bitmask node) bitmask
               (cl-ds.common.rrb:sparse-rrb-node-content node) (make-array (logcount bitmask) :element-type type)))
       (when (> i nodes-count)
         (return-from restore-bitmasks nil))))))



(defun dump-column (column-type column stream)
  (let ((callback (write-elements-callback column-type)))
    (ensure-function callback)
    (cl-ds.common.rrb:sparse-rrb-tree-map
     (cl-ds.dicts.srrb:access-tree column)
     (cl-ds.dicts.srrb:access-shift column)
     :leaf-function (lambda (leaf)
                      (iterate
                        (declare (optimize (speed 3))
                                 (type fixnum i))
                        (with content = (cl-ds.common.rrb:sparse-rrb-node-content leaf))
                        (for i from 0 below (cl-ds.common.rrb:sparse-rrb-node-size leaf))
                        (funcall callback (aref content i) stream)))))
  column)


(defun count-nodes (column &aux (result 0))
  (flet ((impl (node) (declare (ignore node))
           (incf result)))
    (cl-ds.common.rrb:sparse-rrb-tree-map (cl-ds.dicts.srrb:access-tree column)
                                          (cl-ds.dicts.srrb:access-shift column)
                                          :leaf-function #'impl :tree-function #'impl)
    result))


(defun dump-bitmasks (column stream)
  (flet ((impl (node)
           (nibbles:write-ub32/be (cl-ds.common.rrb:sparse-rrb-node-bitmask node)
                                  stream)))
    (cl-ds.common.rrb:sparse-rrb-tree-map (cl-ds.dicts.srrb:access-tree column)
                                          (cl-ds.dicts.srrb:access-shift column)
                                          :leaf-function #'impl :tree-function #'impl))
  column)


(defun read-column (stream header index)
  (bind ((shift (nibbles:read-ub16/be stream))
         (nodes-count (nibbles:read-ub64/be stream))
         (column-type (vellum.header:column-type header index))
         (column (vellum.column:make-sparse-material-column :element-type column-type)))
    (setf (cl-ds.dicts.srrb:access-shift column) shift)
    (restore-bitmasks column stream shift nodes-count)
    (restore-column column-type column stream)
    (setf (cl-ds.dicts.srrb:access-index-bound column) (cl-ds.dicts.srrb:scan-index-bound column))
    (setf (cl-ds.dicts.srrb:access-tree-index-bound column) (cl-ds.dicts.srrb:access-index-bound column))
    column))


(defun read-stream (stream)
  (read-file-header stream)
  (bind ((options-plist (read-object stream))
         (compression (getf options-plist :compression ))
         (table-header (read-object stream))
         (column-count (vellum.header:column-count table-header))
         (columns (make-array column-count))
         (input-stream (make-decompressing-stream compression stream)))
    (iterate
      (for i from 0 below column-count)
      (setf (aref columns i) (read-column input-stream table-header i)))
    (make 'vellum.table:standard-table
          :header table-header
          :columns columns)))


(defun write-column (column stream header index)
  (vellum.column:insert-tail column)
  (bind ((shift (cl-ds.dicts.srrb:access-shift column))
         (column-type (vellum.header:column-type header index)))
    (nibbles:write-ub16/be shift stream)
    (nibbles:write-ub64/be (count-nodes column) stream)
    (dump-bitmasks column stream)
    (dump-column column-type column stream)
    column))


(defun write-stream (table stream options)
  (write-file-header stream)
  (bind ((compression (getf options :compression))
         (table-header (vellum.table:header table))
         (column-count (vellum.header:column-count table-header))
         (output-stream (make-compressing-stream compression stream)))
    (write-object options stream)
    (write-object (vellum.table:header table) stream)
    (iterate
      (for i from 0 below column-count)
      (write-column (vellum.table:column-at table i)
                    output-stream
                    table-header
                    i))
    (unless (eq stream output-stream)
      (close output-stream))
    table))


(defmethod conspack:encode-object ((object vellum.header:column-signature) &key &allow-other-keys)
  (conspack:slots-to-alist (object) vellum.header::type vellum.header::name))


(defmethod conspack:decode-object ((object (eql 'vellum.header:column-signature))
                                   alist
                                   &key &allow-other-keys)
  (conspack:alist-to-slots (alist :class vellum.header:column-signature) vellum.header::type vellum.header::name))


(defmethod conspack:encode-object ((object vellum.header:standard-header) &key &allow-other-keys)
  (conspack:slots-to-alist (object) vellum.header::column-signatures vellum.header::column-names))


(defmethod conspack:decode-object ((object (eql 'vellum.header:standard-header))
                                   alist
                                   &key &allow-other-keys)
  (conspack:alist-to-slots (alist :class vellum.header:standard-header)
    vellum.header::column-signatures vellum.header::column-names))


(defmethod vellum:copy-to ((format (eql :binary))
                           (output stream)
                           input
                           &rest options
                           &key (compression nil))
  (declare (ignore compression))
  (write-stream input output options))


(defmethod vellum:copy-to ((format (eql :binary))
                           output
                           input
                           &rest options
                           &key (compression nil))
  (declare (ignore compression))
  (with-output-to-file (stream output :element-type '(unsigned-byte 8))
    (write-stream input stream options)))


(defmethod vellum:copy-from ((format (eql :binary))
                             (input stream)
                             &rest options
                             &key)
  (declare (ignore options))
  (read-stream input))


(defmethod vellum:copy-from ((format (eql :binary))
                             input
                             &rest options
                             &key)

  (declare (ignore options))
  (with-input-from-file (stream input :element-type '(unsigned-byte 8))
    (read-stream stream)))
