(defsystem "agent-runtime-protocol"
  :version "0.1.0"
  :description "CLOS agent runtime protocol for cl-stack (task lifecycle, workspaces, network policy)"
  :author "egao1980"
  :license "MIT"
  :depends-on ()
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "memory"))
  :in-order-to ((test-op (test-op "agent-runtime-protocol/tests"))))

(defsystem "agent-runtime-protocol/tests"
  :depends-on ("agent-runtime-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "protocol-test")
               (:file "lifecycle-test")
               (:file "restarts-test")
               (:file "demo-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
