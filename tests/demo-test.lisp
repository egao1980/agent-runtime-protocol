(in-package #:agent-runtime-protocol/tests)

(deftest lifecycle-demo-runs
  (load (asdf:system-relative-pathname "agent-runtime-protocol" "examples/lifecycle.lisp"))
  (let ((status (agent-runtime-protocol/demo:run (make-broadcast-stream))))
    (ok (agent-runtime-protocol:runtime-status-p status))
    (ok (eq :running (agent-runtime-protocol:runtime-status-phase status)))))
