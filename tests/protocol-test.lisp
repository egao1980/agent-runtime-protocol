(in-package #:agent-runtime-protocol/tests)

(defun %backend (&optional root)
  (agent-runtime-protocol:make-memory-runtime-backend :root root))

(defun %cond (status type)
  (agent-runtime-protocol:find-runtime-condition status type))

(deftest spec-defaults
  (let ((s (agent-runtime-protocol:make-runtime-task-spec :name "t")))
    (ok (agent-runtime-protocol:runtime-task-spec-p s))
    (ok (equal "t" (agent-runtime-protocol:runtime-task-spec-name s)))
    (ok (null (agent-runtime-protocol:runtime-task-spec-debug s)))
    (ok (null (agent-runtime-protocol:runtime-task-spec-network s)))
    (ok (null (agent-runtime-protocol:runtime-task-spec-secrets s)))))

(deftest secret-ref-inject-and-no-material
  (let ((ref (agent-runtime-protocol:make-secret-ref
              :name "vault" :key "token" :inject :file)))
    (ok (agent-runtime-protocol:secret-ref-p ref))
    (ok (equal "vault" (agent-runtime-protocol:secret-ref-name ref)))
    (ok (equal "token" (agent-runtime-protocol:secret-ref-key ref)))
    (ok (eq :file (agent-runtime-protocol:secret-ref-inject ref)))
    (ok (null (find-symbol "SECRET-REF-MATERIAL" :agent-runtime-protocol)))
    (ok (signals (agent-runtime-protocol:make-secret-ref
                  :name "vault" :key "token" :inject :inline)
                 'agent-runtime-protocol:runtime-error))))

(deftest network-policy-coerces-egress-pairs
  (let ((policy (agent-runtime-protocol:make-runtime-network-policy
                 :egress '(("example.com" 443) ("127.0.0.1" 8080)))))
    (ok (agent-runtime-protocol:runtime-network-policy-p policy))
    (ok (= 2 (length (agent-runtime-protocol:runtime-network-policy-egress policy))))
    (let ((rule (first (agent-runtime-protocol:runtime-network-policy-egress policy))))
      (ok (agent-runtime-protocol:runtime-egress-rule-p rule))
      (ok (equal "example.com" (agent-runtime-protocol:runtime-egress-rule-host rule)))
      (ok (= 443 (agent-runtime-protocol:runtime-egress-rule-port rule))))))

(deftest coerce-task-spec-plist
  (let ((s (agent-runtime-protocol:coerce-runtime-task-spec
            '(:name "n" :image "img" :debug t
              :resources (:cpu 1 :memory 128)
              :workspaces ((:name "ws" :git ((:repo "https://ex/foo.git"
                                              :branch "main" :name "foo"))))
              :secrets ((:name "k" :key "v" :inject :env))))))
    (ok (agent-runtime-protocol:runtime-task-spec-p s))
    (ok (agent-runtime-protocol:runtime-task-spec-debug s))
    (ok (equal '(:cpu 1 :memory 128)
               (agent-runtime-protocol:runtime-task-spec-resources s)))
    (ok (agent-runtime-protocol:runtime-workspace-spec-p
         (first (agent-runtime-protocol:runtime-task-spec-workspaces s))))
    (ok (agent-runtime-protocol:secret-ref-p
         (first (agent-runtime-protocol:runtime-task-spec-secrets s))))))

(deftest apply-ready-conditions
  (let* ((backend (%backend))
         (status (agent-runtime-protocol:apply-task
                  backend
                  (agent-runtime-protocol:make-runtime-task-spec
                   :name "ready-task"
                   :workspaces (list (agent-runtime-protocol:make-runtime-workspace-spec
                                      :name "ws"
                                      :git '((:repo "https://example.com/foo.git"
                                              :branch "main" :name "foo"))))))))
    (ok (agent-runtime-protocol:runtime-status-p status))
    (ok (eq :running (agent-runtime-protocol:runtime-status-phase status)))
    (ok (agent-runtime-protocol:runtime-condition-status
         (%cond status :workspace-ready)))
    (ok (agent-runtime-protocol:runtime-condition-status
         (%cond status :gateway-ready)))
    (ok (agent-runtime-protocol:runtime-condition-status
         (%cond status :ready)))
    (let ((ws (agent-runtime-protocol:memory-runtime-workspace-path
               backend "ready-task" "ws")))
      (ok (probe-file (merge-pathnames ".runtime-workspace" ws)))
      (ok (probe-file (merge-pathnames "foo/.runtime-git" ws))))
    (let ((described (agent-runtime-protocol:describe-task backend "ready-task"))
          (watched (agent-runtime-protocol:watch-task backend "ready-task")))
      (ok (eq :running (agent-runtime-protocol:runtime-status-phase described)))
      (ok (eq :running (agent-runtime-protocol:runtime-status-phase watched))))))

(deftest exec-in-task-denied-without-debug
  (let* ((backend (%backend))
         (spec (agent-runtime-protocol:make-runtime-task-spec :name "no-debug")))
    (agent-runtime-protocol:apply-task backend spec)
    (ok (signals (agent-runtime-protocol:exec-in-task backend "no-debug" '("echo" "hi"))
                 'agent-runtime-protocol:runtime-denied))))

(deftest exec-in-task-allowed-with-debug
  (let* ((backend (%backend))
         (spec (agent-runtime-protocol:make-runtime-task-spec
                :name "debugged" :debug t)))
    (agent-runtime-protocol:apply-task backend spec)
    (let ((result (agent-runtime-protocol:exec-in-task
                   backend "debugged" '("echo" "hi"))))
      (ok (eql 0 (getf result :exit-code)))
      (ok (equal '("echo" "hi") (getf result :argv))))))

(deftest describe-unknown-task
  (ok (signals (agent-runtime-protocol:describe-task (%backend) "missing")
               'agent-runtime-protocol:runtime-not-found)))
