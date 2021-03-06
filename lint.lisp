;;; -*- Mode: LISP; Syntax: Common-lisp; Package: (LINT SCL); Base: 10 -*-

;;; This implements a set of compiler style checkers that warn when a function call
;;; does not conform to Common Lisp.

;;; To disable the checks after loading this, set LINT:*CHECK-PORTABILITY* to NIL.

;;; *********************** CHANGE LOG *******************
;;;
;;; 12/01/87 20:08:59 Barmar:  Created.
;;;
;;; 12/02/87 13:12:26 Salem:  Changed loop.
;;; 12/02/87 13:12:31 Salem:  Added *check-loop-portability*.
;;;
;;; 12/02/87 18:57:52 Barmar:  Added lots more checks.
;;;
;;; 12/03/87 23:52:38 Barmar:  Added the.
;;;
;;; 12/08/87 15:05:09 Barmar:  Added *check-function*,
;;; flavor::compose-method-combination, and changed function.  Prevent warning about
;;; #'(flavor:method ...) references when compiling combined methods.
;;;
;;; 12/09/87 22:05:42 Salem:  Changed loop.  fixed *CHECK-LOOP-PORTABILITY* bug
;;;
;;; 12/11/87 18:45:27 Barmar:  Changed deflint.  Changed the expansion so that the
;;; DEFLINT body will be in a lambda expression, which makes declarations
;;; work right.  Set up a BLOCK so that you can RETURN-FROM the name of the function.
;;;
;;; 12/11/87 18:46:33 Barmar:  Changed function.  Allow function specs produced by
;;; DEFSTRUCT and DEFINE-SETF-METHOD.
;;;
;;; 12/11/87 19:02:59 Barmar:  Changed dribble.  Warns if used, since it is not
;;; portable inside functions.
;;;
;;; 12/14/87 03:16:09 Barmar:  Changed deflint and added *nonportable-packages*.
;;; Doesn't warn when compiling in a Symbolics package.
;;;
;;; 12/14/87 03:22:39 Barmar:  Changed with-open-file.  Changed to use a legal
;;; function lambda list.
;;;
;;; 12/14/87 03:23:04 Barmar:  Changed &body's in deflint forms to &rest.
;;;
;;; 2/02/88 12:26:42 Barmar:  Changed deflint.  Reversed the *nonportable-packages*
;;; check.
;;;
;;; 6/13/89 11:26:40 Barmar:  Changed flavor::compose-method-combination.  Changed
;;; advise to si:advise-permanently.
;;;
#| *************** END OF CHANGE LOG ***************|#


(cl:in-package :lint-internal)

(def-suite lint)

(in-suite lint)

(defvar *check-portability* t
  "Controls whether the Common Lisp portability checker is invoked.")

(defvar *check-loop-portability* nil
  "Controls whether the Common Lisp portability checker is invoked on LOOP forms.")

(defparameter *nonportable-packages*
	      (list (find-package "SYMBOLICS-COMMON-LISP")
		    (find-package "ZETALISP")))

#+symbolics
(defprop deflint "Portability style checker" si:definition-type-name)

(progn
  ;; test helpers
  (defmacro warn-to-string (expr)
    `(with-output-to-string (*error-output*)
       ,expr))

  (defmacro setup-test (&body body)
    `(progn ,@body))
  )

(defmacro deflint (function-name arglist &body body &aux (arg-var (gensym "ARGL")))
  "Defines a portability style checker.
FUNCTION-NAME is the name of a function, macro, or special form, whose invocation
will be checked.
ARGLIST is the argument list syntax.
BODY is an implicit progn; if its value is non-null then it should be a character
string indicating what is wrong (this will be used in the compiler warning).
The body can access the parameters specified in arglist, as well as the variable
named ARGLIST, which holds the entire argument list."
  `(progn
     (put-style-checker ',function-name 'lint
      (lambda (,arg-var)
        (when (and *check-portability*
                   (or (null *package*)
                       (null
			(intersection *nonportable-packages*
                                      (package-use-list *package*)))))
          (let* ((arglist (cdr ,arg-var))
                 (result
		  (block ,function-name
		    (apply #'(lambda ,arglist
			       .,body)
			   arglist))))
            (when result
              (lint-warn ,arg-var result))))))))

(def-suite deflint :in lint)

(in-suite deflint)

(test deflint-rest
  (setup-test
    (remove-style-checker 'foo 'lint)
    (deflint foo (&rest form)
      (format nil "test1: ~S" form)))
  (is (string=
       "STYLE-WARNING: Non-portable code: NIL
  test1: NIL
"
       (warn-to-string
        (call-style-checkers 'foo () )))))

(test deflint-a-b-rest
  (setup-test
    (remove-style-checker 'foo 'lint)
    (deflint foo (a b &rest form)
      (format nil "test2 ~S ~S ~S" a b form)))
  (is (string=
       "STYLE-WARNING: Non-portable code: (A B C D E)
  test2 B C (D E)
"
       (warn-to-string
        (call-style-checkers 'foo '(a b c d e))) )))

(defun lint-warn (form complaint)
  #-sbcl (warn "Non-portable code: ~S~%  ~A" form complaint)
  #+sbcl (sb-c::compiler-style-warn "Non-portable code: ~S~%  ~A" form complaint))

(test lint-warn
  (is (string= (warn-to-string (lint-warn "form" "complaint"))
                 "STYLE-WARNING: Non-portable code: \"form\"
  complaint
")))


(in-suite lint)

(defmacro defscl (function-name)
  ;; Def Symbolics Common Lisp ?
  `(progn
     (deflint ,function-name (&rest ignore)
       (declare (ignore ignore))
       (format nil "~S isn't in Common Lisp." ',function-name))))

(test defscl
  (setup-test
    (remove-style-checker 'foo 'lint)
    (defscl foo))
  (is (string=
       "STYLE-WARNING: Non-portable code: NIL
  FOO isn't in Common Lisp.
"
       (warn-to-string
        (call-style-checkers 'foo () )))))

(defmacro deflint-bad-optional (function-name arglist bad-optionals &body body)
  (let* ((opt-arglist
	   (loop for option in bad-optionals
		 collect `(,(gensym "IGNORE-") nil ,option)))
	 (cond-clauses
	   (loop for option in bad-optionals
		 collect `(,option
			   ,(format nil "~S argument to ~S is nonstandard." option function-name))))
	 (new-arglist
	   (append arglist (if (member '&optional arglist) nil
			       '(&optional))
		   opt-arglist)))
    `(deflint ,function-name ,new-arglist
       ;; (declare (sys:function-parent ,function-name deflint-bad-optional))
       (cond ,@cond-clauses
	     (t (progn .,body))))))

(test deflint-bad-optional
  (setup-test
    (remove-style-checker 'functionp 'lint)
    (deflint-bad-optional functionp (ignore) (allow-special-forms)))
  (is (string=
       (warn-to-string
        (call-style-checkers 'functionp
                             '(functionp &optional allow-special-forms) ))
       "STYLE-WARNING: Non-portable code: (FUNCTIONP &OPTIONAL ALLOW-SPECIAL-FORMS)
  ALLOW-SPECIAL-FORMS argument to FUNCTIONP is nonstandard.
"
       )))

(defmacro deflint-bad-keywords (function-name arglist bad-keys &body body)
  (let* ((key-arglist
	   (loop for key in bad-keys
		 collect `((,(intern (symbol-name key) :keyword) ,(gensym "IGNORE-"))
			   nil ,key)))
	 (cond-clauses
	   (loop for key in bad-keys
		 collect `(,key
			   ,(format nil "~S argument to ~S is nonstandard."
				    (intern (symbol-name key) :keyword)
				    function-name))))
	 (new-arglist
	   (append arglist (if (member '&key arglist) nil
			       '(&key))
		   key-arglist)))
    `(deflint ,function-name ,new-arglist
       (cond ,@cond-clauses
	     (t (progn .,body))))))

(test deflint-bad-keywords
  (setup-test
    (remove-style-checker 'make-sequence 'lint)
    (deflint-bad-keywords make-sequence
                          (#:ignore #:ignore &key ((:initial-element #:ignore)))
                          (area)))
  (is (string=
       (warn-to-string
        (call-style-checkers 'make-sequence
                             '(make-sequence 1 2 :initial-element 8 :area 3) ))
       "STYLE-WARNING: Non-portable code: (MAKE-SEQUENCE 1 2 :INITIAL-ELEMENT 8 :AREA 3)
  :AREA argument to MAKE-SEQUENCE is nonstandard.
"
       )))

;;; The following section of this file is DEFLINT forms for functions defined in
;;; CLtL, in the order that their descriptions appear.

(clear-style-checker-suite 'lint)

;;; This won't get invoked because top-level forms aren't style-checked, sigh...
(deflint defun (name lambda-list &rest ignore)
  (declare (ignore ignore))
  (cond ((not (symbolp name))
	 (format nil "Function name ~S is not a symbol." name))
	((not (listp lambda-list))
	 (format nil "Function argument list ~S is not a list." lambda-list))))

(test defun
  (is-false (call-style-checkers 'defun
                                 '(defun foo () )))
  (is (string=
       (warn-to-string
        (call-style-checkers 'defun
                             '(defun (:property foo bar) () )))
       "STYLE-WARNING: Non-portable code: (DEFUN (:PROPERTY FOO BAR) ())
  Function name (:PROPERTY FOO BAR) is not a symbol.
"
       ))
  (is (string=
       (warn-to-string
        (call-style-checkers 'defun
                             '(defun foo bar) ))
       "STYLE-WARNING: Non-portable code: (DEFUN FOO BAR)
  Function argument list BAR is not a list.
"
       )))

#-ANSI-CL
(deflint lambda (&rest ignore)
  "LAMBDA expression not inside a FUNCTION special form.")

(defvar *check-function* t
  "Set to NIL to disable checking for non-portable FUNCTION arguments.")

;(si:advise-permanently flavor::compose-method-combination :around function-lint-kludge nil
;  (let ((*check-function* nil))
;    :do-it))

(deflint function (arg)
  (and *check-function*
       (listp arg)
       (not (or (eq (car arg) 'lambda)
		;; Allow some forms produced by Common Lisp macros
		;; First (:property <x> named-structure-invoke) generated by
		;; DEFSTRUCT, and (:property <x> lt::setf-method-internal) generated
		;; by DEFINE-SETF-METHOD
		(and (eq (car arg) ':property)
                     ;; lt ???
		     #|(member (third arg) '(named-structure-invoke lt::setf-method-internal))|#)
		;; (zl:named-lambda (:print-self) ...) is generated by DEFSTRUCT.
                ;; ???
		#|(and (eq (car arg) 'zl:named-lambda)
		     (equal (cadr arg) '(:print-self)))|#))
       (format nil "~S is not a symbol or lambda-expression." arg)))

(test function
  (is-false (call-style-checkers 'function
                                 '(function foo) ))
  (is (string=
       (warn-to-string
        (call-style-checkers 'function
                             '(function (foo)) ))
       "STYLE-WARNING: Non-portable code: #'(FOO)
  (FOO) is not a symbol or lambda-expression.
"
       )))

#-ANSI-CL
(deflint-bad-optional get-setf-method (ignore) (for-effect))

#+ANSI-CL
(deflint-bad-optional get-setf-expansion (ignore) (for-effect))

(test get-setf-expansion
  (remove-style-checker 'get-setf-expansion 'lint)
  (is-false (call-style-checkers 'get-setf-expansion
                                 '(get-setf-expansion (setf car)))))

#-ANSI-cl
(deflint-bad-optional get-setf-method-multiple-value (ignore) (for-effect))

(deflint let (varlist &rest ignore)
  (declare (ignore ignore))
  (check-varlist varlist))

(test let
  (is-false (call-style-checkers 'let
                                 '(let (foo))))
  (is-false (call-style-checkers 'let
                                 '(let ((foo 1) (bar 2))))))

(deflint let* (varlist &rest ignore)
  (declare (ignore ignore))
  (check-varlist varlist))

(deflint compiler-let (varlist &rest ignore)
  (declare (ignore ignore))
  (check-varlist varlist))

(defun check-varlist (varlist)
  (dolist (var varlist)
    (and (consp var)
	 (null (cdr var))
	 (return (format nil "No value specified in binding ~S." var)))))

#||||
(deflint if (#:ignore #:ignore &optional #:ignore &rest extra)
  (when extra
    "Too many else clauses in IF form."))

(deflint loop (&rest forms)
  (unless (or (null *check-loop-portability*) (every #'listp forms))
    "All LOOP subforms must be lists."))

(deflint-bad-optional macroexpand (ignore &optional ignore) (dont-expand-special-forms))

(deflint-bad-optional macroexpand-1 (ignore &optional ignore) (dont-expand-special-forms))

#|(deflint the (type-spec ignore)
  (if (nth-value 1 (ignore-errors
                     (find-class type-spec)))	;signals an error if type-spec invalid
      (format nil "~S is not a known type specifier." type-spec)
      (values)))|#

(deflint the (type-spec ignore)
  (unless (ignore-errors
	    (progn #|(cli::type-expand type-spec)|#	;signals an error if type-spec invalid
		   t))
    (format nil "~S is not a known type specifier." type-spec)))

(deflint-bad-optional make-symbol (ignore) (permanent-p))

(deflint-bad-keywords make-package (ignore &key ((:nicknames ignore)) ((:use ignore)))
		      (prefix-name shadow export import shadowing-import
				   import-from relative-names relative-names-for-me size
				   external-only new-symbol-function
				   hash-inherited-symbols invisible
				   colon-mode prefix-intern-function include))

(deflint unintern (ignore &optional (ignore nil package-p))
  (unless package-p
    "Symbolics UNINTERN has a nonstandard default for PACKAGE."))

(deflint-bad-optional copy-seq (ignore) (area))

(deflint-bad-keywords make-sequence (ignore ignore &key ((:initial-element ignore)))
		      (area))

(deflint-bad-keywords delete-duplicates (ignore &key ((:test ignore)) ((:test-not ignore))
						((:start ignore)) ((:end ignore))
						((:from-end ignore)) ((:key ignore)))
		      (replace))

(deflint-bad-keywords make-list (ignore &key ((:initial-element ignore)))
		      (area))

(deflint-bad-optional copy-list (ignore) (area force-dotted))

(deflint-bad-optional copy-alist (ignore) (area))

(deflint-bad-keywords push (ignore ignore) (area localize))

(deflint-bad-keywords pushnew (ignore ignore &key ((:key ignore))
				      ((:test ignore))
				      ((:test-not ignore))
				      )
		      (area localize))

(deflint-bad-keywords assoc-if (ignore ignore) (key))
(deflint-bad-keywords assoc-if-not (ignore ignore) (key))

(deflint-bad-keywords rassoc-if (ignore ignore) (key))
(deflint-bad-keywords rassoc-if-not (ignore ignore) (key))

(deflint-bad-keywords make-hash-table (&key ((:test ignore)) ((:size ignore))
					    ((:rehash-size ignore))
					    ((:rehash-threshold ignore)))
		      (area hash-function rehash-before-cold rehash-after-full-gc
			    entry-size number-of-values store-hash-code mutating
			    initial-contents optimizations locking ignore-gc
			    growth-factor growth-threshold))


(deflint-bad-keywords make-array (ignore &key ((:element-type ignore))
					 ((:initial-element ignore))
					 ((:initial-contents ignore))
					 ((:adjustable ignore)) ((:fill-pointer ignore))
					 ((:displaced-to ignore))
					 ((:displaced-index-offset ignore)))
		      (displaced-conformally area leader-list leader-length
					     named-structure-symbol))

(deflint-bad-optional vector-pop (ignore) (default))

(deflint-bad-keywords adjust-array (ignore ignore &key
					   ((:element-type ignore))
					   ((:initial-element ignore))
					   ((:initial-contents ignore))
					   ((:fill-pointer ignore))
					   ((:displaced-to ignore))
					   ((:displaced-index-offset ignore)))
		      (displaced-conformally))

(deflint-bad-keywords make-string (ignore &key ((:initial-element ignore)))
		      (element-type area))

(deflint defstruct (name-and-options &rest ignore)
  (when (listp name-and-options)
    (let ((bad-option
	    (find-if #'(lambda (option)
			 (member option
				 '(:alterant :but-first :callable-accessors
					     :default-pointer :eval-when :make-list
					     :make-array :print :property :size-symbol
					     :size-macro :times
					     :constructor-make-array-keywords)))
		     (cdr name-and-options)
		     :key #'(lambda (item)
			      (if (atom item) item
				  (car item))))))
      (when bad-option
	(format nil "Nonstandard DEFSTRUCT option ~S." bad-option)))))

(deflint-bad-optional eval (ignore) (environment))

(deflint evalhook (ignore ignore &optional (ignore nil applyhook-supplied) ignore)
  (unless applyhook-supplied
    "APPLYHOOKFN argument to EVALHOOK is required."))

(deflint make-echo-stream (ignore ignore)
  "Symbolics doesn't implement MAKE-ECHO-STREAM.")

(deflint-bad-keywords write (ignore &key ((:stream ignore)) ((:escape ignore))
				    ((:radix ignore))
				    ((:base ignore)) ((:circle ignore)) ((:pretty ignore))
				    ((:level ignore)) ((:length ignore)) ((:case ignore))
				    ((:gensym ignore)) ((:array ignore)))
		      (array-length string-length bit-vector-length abbreviate-quote
				    readably structure-contents))

(deflint-bad-keywords write-to-string
		      (ignore &key ((:escape ignore)) ((:radix ignore))
				    ((:base ignore)) ((:circle ignore)) ((:pretty ignore))
				    ((:level ignore)) ((:length ignore)) ((:case ignore))
				    ((:gensym ignore)) ((:array ignore)))
		      (array-length string-length readably structure-contents))

(deflint format (ignore control-string &rest ignore)
  (when (stringp control-string)
    (let ((bad-control (find-bad-format-control control-string)))
      (when bad-control
	(format nil "Nonstandard FORMAT operation: ~A." bad-control)))))

(defun find-bad-format-control (string)
  ;; to be supplied -- this is hard
  string
  nil)

(deflint open (ignore &rest keywords)
  (loop for keyword in keywords by #'cddr
	unless (member keyword '(:direction :element-type :if-exists :if-does-not-exist))
	  return (format nil "Nonstandard OPEN keyword ~S." keyword)
	finally (return nil)))

;;; This will actually generate two warnings, one from this and one from OPEN.
(deflint with-open-file (open-args &rest ignore)
  (destructuring-bind (ignore ignore &rest keywords) open-args
    (loop for keyword in keywords by #'cddr
	  unless (member keyword '(:direction :element-type :if-exists :if-does-not-exist))
	    return (format nil "Nonstandard OPEN keyword ~S." keyword)
	  finally (return nil))))

(deflint-bad-keywords load (ignore &key ((:verbose ignore)) ((:print ignore))
				   ((:if-does-not-exist ignore)))
		      (package set-default-pathname))

(deflint-bad-keywords pathname (ignore) (deleted))

(deflint cerror (first-arg &rest ignore)
  (when (constantp first-arg)
    (let ((value (eval first-arg)))
      (unless (stringp value)
	(format nil "First argument to CERROR must be a FORMAT control string, not ~S."
		value)))))

(deflint warn (first-arg &rest ignore)
  (when (constantp first-arg)
    (let ((value (eval first-arg)))
      (unless (stringp value)
	(format nil "First argument to WARN must be a FORMAT control string, not ~S."
		value)))))

(deflint-bad-keywords compile-file (ignore &key ((:output-file ignore)))
		      (package load set-default-pathname))

(deflint-bad-optional disassemble (ignore) (from-pc to-pc))

(deflint trace (&rest functions)
  (unless (every #'symbolp functions)
    "All arguments to TRACE must be symbols."))

(deflint untrace (&rest functions)
  (unless (every #'symbolp functions)
    "All arguments to UNTRACE must be symbols."))

(deflint-bad-optional time (ignore) (describe-consing))

(deflint-bad-optional describe (ignore) (no-complaints))

(deflint inspect (&optional (ignore nil object-p))
  (unless object-p
    "OBJECT-P argument to INSPECT must be supplied."))

(deflint room (&optional ignore &rest args)
  (when args
    "More than one optional argument to ROOM is nonstandard."))

(deflint-bad-optional dribble (&optional ignore) (editor-p)
  "DRIBBLE should only be used interactively at top-level.")

(deflint-bad-optional apropos (ignore &optional ignore)
		      (do-inherited-symbols do-packages-used-by))

(deflint-bad-optional apropos-list (ignore &optional ignore)
		      (do-packages-used-by))
||||#