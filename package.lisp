;;;; package.lisp

(cl:in-package :cl-user)

(defpackage :lint
  (:export :*check-portability* :*check-loop-portability* :*check-function*
           :deflint :deflint-bad-optional :deflint-bad-keywords
           :defscl))

(defpackage :lint-internal
  (:use :lint :cl :fiveam))

