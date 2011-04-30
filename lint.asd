;;;; lint.asd

(cl:in-package :asdf)

(defsystem :lint
  :serial t
  :components ((:file "package")
               (:file "lint")))

(defmethod perform ((o test-op) (c (eql (find-system :lint))))
  (load-system :lint)
  (or (flet ((_ (pkg sym)
               (intern (symbol-name sym) (find-package pkg))))
         (let ((result (funcall (_ :fiveam :run) (_ :lint-internal :lint))))
           (funcall (_ :fiveam :explain!) result)
           (funcall (_ :fiveam :results-status) result)))
      (error "test-op failed") ))

