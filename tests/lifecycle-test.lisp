(in-package #:agent-runtime-protocol/tests)

(defun %fresh-backend ()
  (agent-runtime-protocol:make-memory-runtime-backend))

(defun %apply (backend &key (name "life") debug
                         (workspaces
                          (list (agent-runtime-protocol:make-runtime-workspace-spec
                                 :name "ws"
                                 :git '((:repo "https://example.com/foo.git"
                                         :branch "main" :name "foo"))))))
  (agent-runtime-protocol:apply-task
   backend
   (agent-runtime-protocol:make-runtime-task-spec
    :name name :debug debug :workspaces workspaces)))

(deftest suspend-clears-ready
  (let* ((backend (%fresh-backend)))
    (%apply backend :name "s1")
    (let* ((suspended (agent-runtime-protocol:suspend-task backend "s1"))
           (ready (agent-runtime-protocol:find-runtime-condition
                   suspended :ready)))
      (ok (eq :suspended (agent-runtime-protocol:runtime-status-phase suspended)))
      (ok (null (agent-runtime-protocol:runtime-condition-status ready)))
      (ok (eq :task-suspended (agent-runtime-protocol:runtime-condition-reason ready))))))

(deftest resume-restores-workspace-files
  (let* ((backend (%fresh-backend))
         (name "restore"))
    (%apply backend :name name)
    (let* ((ws (agent-runtime-protocol:memory-runtime-workspace-path backend name "ws"))
           (notes (merge-pathnames "notes.txt" ws)))
      (with-open-file (out notes :direction :output :if-exists :supersede
                           :if-does-not-exist :create)
        (write-string "keep-me" out))
      (ok (probe-file notes))
      (agent-runtime-protocol:suspend-task backend name)
      (ok (null (probe-file notes)))
      (let ((resumed (agent-runtime-protocol:resume-task backend name)))
        (ok (eq :running (agent-runtime-protocol:runtime-status-phase resumed)))
        (ok (agent-runtime-protocol:runtime-condition-status
             (agent-runtime-protocol:find-runtime-condition resumed :ready)))
        (ok (probe-file notes))
        (ok (equal "keep-me" (uiop:read-file-string notes)))))))

(deftest delete-forgets-task
  (let* ((backend (%fresh-backend)))
    (%apply backend :name "gone")
    (let ((deleted (agent-runtime-protocol:delete-task backend "gone")))
      (ok (eq :terminating (agent-runtime-protocol:runtime-status-phase deleted)))
      (ok (signals (agent-runtime-protocol:describe-task backend "gone")
                   'agent-runtime-protocol:runtime-not-found))
      (ok (signals (agent-runtime-protocol:suspend-task backend "gone")
                   'agent-runtime-protocol:runtime-not-found)))))

(deftest invalid-phase-suspend-when-suspended
  (let ((backend (%fresh-backend)))
    (%apply backend :name "twice")
    (agent-runtime-protocol:suspend-task backend "twice")
    (ok (signals (agent-runtime-protocol:suspend-task backend "twice")
                 'agent-runtime-protocol:runtime-invalid-phase))))

(deftest invalid-phase-resume-when-running
  (let ((backend (%fresh-backend)))
    (%apply backend :name "awake")
    (ok (signals (agent-runtime-protocol:resume-task backend "awake")
                 'agent-runtime-protocol:runtime-invalid-phase))))

(deftest invalid-phase-reapply
  (let ((backend (%fresh-backend)))
    (%apply backend :name "dup")
    (ok (signals (%apply backend :name "dup")
                 'agent-runtime-protocol:runtime-invalid-phase))))
