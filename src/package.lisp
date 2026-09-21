(defpackage #:agent-runtime-protocol
  (:use #:cl)
  (:nicknames #:stack-runtime)
  (:export #:runtime-error
           #:runtime-error-message
           #:runtime-error-id
           #:runtime-error-phase
           #:runtime-not-found
           #:runtime-denied
           #:runtime-denied-policy
           #:runtime-invalid-phase
           #:runtime-invalid-phase-expected
           #:retry

           #:runtime-backend
           #:*runtime-backend*

           #:runtime-egress-rule
           #:runtime-egress-rule-p
           #:make-runtime-egress-rule
           #:runtime-egress-rule-host
           #:runtime-egress-rule-port

           #:runtime-network-policy
           #:runtime-network-policy-p
           #:make-runtime-network-policy
           #:runtime-network-policy-egress
           #:runtime-network-policy-listeners

           #:secret-ref
           #:secret-ref-p
           #:make-secret-ref
           #:secret-ref-name
           #:secret-ref-key
           #:secret-ref-inject

           #:runtime-workspace-spec
           #:runtime-workspace-spec-p
           #:make-runtime-workspace-spec
           #:runtime-workspace-spec-name
           #:runtime-workspace-spec-path
           #:runtime-workspace-spec-git
           #:runtime-workspace-spec-mcp
           #:runtime-workspace-spec-skills
           #:runtime-workspace-spec-goal

           #:runtime-task-spec
           #:runtime-task-spec-p
           #:make-runtime-task-spec
           #:coerce-runtime-task-spec
           #:runtime-task-spec-name
           #:runtime-task-spec-image
           #:runtime-task-spec-command
           #:runtime-task-spec-workspaces
           #:runtime-task-spec-network
           #:runtime-task-spec-resources
           #:runtime-task-spec-secrets
           #:runtime-task-spec-debug

           #:runtime-condition
           #:runtime-condition-p
           #:make-runtime-condition
           #:runtime-condition-type
           #:runtime-condition-status
           #:runtime-condition-reason
           #:find-runtime-condition

           #:runtime-status
           #:runtime-status-p
           #:make-runtime-status
           #:runtime-status-phase
           #:runtime-status-conditions
           #:runtime-status-snapshot-ref
           #:runtime-status-worker-id

           #:apply-task
           #:describe-task
           #:watch-task
           #:suspend-task
           #:resume-task
           #:delete-task
           #:exec-in-task

           #:memory-runtime-backend
           #:memory-runtime-backend-root
           #:make-memory-runtime-backend
           #:use-memory-runtime-backend
           #:memory-runtime-workspace-path))

(in-package #:agent-runtime-protocol)
