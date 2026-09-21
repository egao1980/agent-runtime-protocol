;;;; Memory-backend lifecycle demo — apply → Ready, suspend, resume files.
;;;;   sbcl --load examples/lifecycle.lisp

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package :agent-runtime-protocol)
    (require :asdf)
    (asdf:load-system "agent-runtime-protocol")))

(defpackage #:agent-runtime-protocol/demo
  (:use #:cl #:agent-runtime-protocol)
  (:export #:run))

(in-package #:agent-runtime-protocol/demo)

(defun run (&optional (stream *standard-output*))
  "Drive the in-memory runtime. Returns the resumed RUNTIME-STATUS."
  (let* ((backend (make-memory-runtime-backend))
         (spec (make-runtime-task-spec
                :name "demo"
                :workspaces (list (make-runtime-workspace-spec
                                   :name "ws"
                                   :git '((:repo "https://example.com/foo.git"
                                           :branch "main" :name "foo"))))
                :network (make-runtime-network-policy
                          :egress '(("example.com" 443)))
                :secrets (list (make-secret-ref
                                :name "vault" :key "token" :inject :env))))
         (ready (apply-task backend spec))
         (ws (memory-runtime-workspace-path backend "demo" "ws"))
         (notes (merge-pathnames "notes.txt" ws)))
    (assert (eq :running (runtime-status-phase ready)))
    (assert (runtime-condition-status (find-runtime-condition ready :ready)))
    (assert (null (find-symbol "SECRET-REF-MATERIAL" :agent-runtime-protocol)))
    (with-open-file (out notes :direction :output :if-exists :supersede)
      (write-string "keep-me" out))
    (let ((suspended (suspend-task backend "demo")))
      (assert (eq :suspended (runtime-status-phase suspended)))
      (assert (eq :task-suspended
                  (runtime-condition-reason
                   (find-runtime-condition suspended :ready)))))
    (uiop:delete-file-if-exists notes)
    (let ((resumed (resume-task backend "demo")))
      (format stream "~&; apply=~s suspend=:suspended resume=~s notes=~s~%"
              (runtime-status-phase ready)
              (runtime-status-phase resumed)
              (uiop:read-file-string notes))
      (assert (eq :running (runtime-status-phase resumed)))
      (assert (equal "keep-me" (uiop:read-file-string notes)))
      (delete-task backend "demo")
      resumed)))

#+sbcl
(when (and *load-truename*
           (equal (pathname-name *load-truename*) "lifecycle")
           (find "examples/lifecycle.lisp" sb-ext:*posix-argv* :test #'search))
  (run)
  (uiop:quit 0))
