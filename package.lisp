;;;; package.lisp

(cl:in-package :cl-user)

(defpackage :lint
  (:export))

(defpackage :lint-internal
  (:use :lint :cl :fiveam))

