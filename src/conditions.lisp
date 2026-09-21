(in-package #:agent-runtime-protocol)

(define-condition runtime-error (error)
  ((message :initarg :message :reader runtime-error-message :initform nil)
   (id :initarg :id :reader runtime-error-id :initform nil)
   (phase :initarg :phase :reader runtime-error-phase :initform nil))
  (:report (lambda (c s)
             (format s "runtime error~@[ (~s)~]~@[: ~a~]"
                     (runtime-error-id c)
                     (runtime-error-message c)))))

(define-condition runtime-not-found (runtime-error) ()
  (:report (lambda (c s)
             (format s "runtime task not found~@[ (~s)~]~@[: ~a~]"
                     (runtime-error-id c)
                     (runtime-error-message c)))))

(define-condition runtime-denied (runtime-error)
  ((policy :initarg :policy :reader runtime-denied-policy :initform nil))
  (:report (lambda (c s)
             (format s "runtime denied~@[ (~a)~]~@[ for ~s~]~@[: ~a~]"
                     (runtime-denied-policy c)
                     (runtime-error-id c)
                     (runtime-error-message c)))))

(define-condition runtime-invalid-phase (runtime-error)
  ((expected :initarg :expected :reader runtime-invalid-phase-expected
             :initform nil))
  (:report (lambda (c s)
             (format s "runtime invalid phase~@[ (~s)~]~@[ is ~s~]~@[ expected ~s~]~@[: ~a~]"
                     (runtime-error-id c)
                     (runtime-error-phase c)
                     (runtime-invalid-phase-expected c)
                     (runtime-error-message c)))))
