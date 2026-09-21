(in-package #:agent-runtime-protocol/tests)

(deftest apply-task-use-value
  (let ((backend (agent-runtime-protocol:make-memory-runtime-backend))
        (supplied (agent-runtime-protocol:make-runtime-status
                   :phase :running
                   :conditions (list (agent-runtime-protocol:make-runtime-condition
                                      :type :ready :status t))))
        (got nil))
    (handler-bind ((agent-runtime-protocol:runtime-error
                    (lambda (c)
                      (declare (ignore c))
                      (use-value supplied))))
      (setf got (agent-runtime-protocol:apply-task
                 backend
                 (agent-runtime-protocol:make-runtime-task-spec))))
    (ok (eq supplied got))
    (ok (eq :running (agent-runtime-protocol:runtime-status-phase got)))))

(deftest apply-task-abort
  (let ((backend (agent-runtime-protocol:make-memory-runtime-backend))
        (got :unset))
    (handler-bind ((agent-runtime-protocol:runtime-error
                    (lambda (c)
                      (abort c))))
      (setf got (agent-runtime-protocol:apply-task
                 backend
                 (agent-runtime-protocol:make-runtime-task-spec))))
    (ok (null got))))

(deftest apply-task-retry
  (let ((backend (agent-runtime-protocol:make-memory-runtime-backend))
        (attempts 0)
        (got nil)
        (supplied (agent-runtime-protocol:make-runtime-status :phase :failed)))
    (handler-bind ((agent-runtime-protocol:runtime-error
                    (lambda (c)
                      (declare (ignore c))
                      (incf attempts)
                      (if (< attempts 2)
                          (invoke-restart 'agent-runtime-protocol:retry)
                          (use-value supplied)))))
      (setf got (agent-runtime-protocol:apply-task
                 backend
                 (agent-runtime-protocol:make-runtime-task-spec))))
    (ok (>= attempts 2))
    (ok (eq supplied got))))
