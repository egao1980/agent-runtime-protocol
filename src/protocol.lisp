(in-package #:agent-runtime-protocol)

;;; Long-lived suspendable fenced tasks. One-shot run-sandboxed stays on
;;; compute-protocol. Network and secret-ref types live here so this repo
;;; is self-contained (no :depends-on compute-protocol).

(defclass runtime-backend () ())

(defvar *runtime-backend* nil)

(defparameter *runtime-phases*
  '(:pending :running :suspended :failed :terminating))

(defparameter *runtime-condition-types*
  '(:workspace-ready :gateway-ready :ready))

;;; --- network ----------------------------------------------------------------

(defclass runtime-egress-rule ()
  ((host :initarg :host :reader runtime-egress-rule-host)
   (port :initarg :port :reader runtime-egress-rule-port))
  (:documentation "Allowlisted egress (HOST PORT). HOST is a hostname or address."))

(defun runtime-egress-rule-p (object)
  (typep object 'runtime-egress-rule))

(defun make-runtime-egress-rule (&key host port)
  (check-type host string)
  (check-type port (integer 1 65535))
  (make-instance 'runtime-egress-rule :host host :port port))

(defun %coerce-egress-rule (item)
  (etypecase item
    (runtime-egress-rule item)
    (cons
     (make-runtime-egress-rule :host (if (stringp (first item))
                                         (first item)
                                         (princ-to-string (first item)))
                               :port (second item)))))

(defclass runtime-network-policy ()
  ((egress :initarg :egress :reader runtime-network-policy-egress :initform nil)
   (listeners :initarg :listeners :reader runtime-network-policy-listeners
              :initform nil))
  (:documentation
   "EGRESS is a list of RUNTIME-EGRESS-RULE. LISTENERS is optional backend-specific."))

(defun runtime-network-policy-p (object)
  (typep object 'runtime-network-policy))

(defun make-runtime-network-policy (&key egress listeners)
  (make-instance 'runtime-network-policy
                 :egress (mapcar #'%coerce-egress-rule egress)
                 :listeners listeners))

(defun %coerce-network (network)
  (cond
    ((null network) nil)
    ((member network '(:none :allow)) network)
    ((runtime-network-policy-p network) network)
    ((and (consp network) (keywordp (car network)))
     (apply #'make-runtime-network-policy network))
    ((consp network)
     (make-runtime-network-policy :egress network))
    (t
     (error 'runtime-error
            :message (format nil "invalid network policy: ~s" network)))))

;;; --- secrets ----------------------------------------------------------------

(defclass secret-ref ()
  ((name :initarg :name :reader secret-ref-name)
   (key :initarg :key :reader secret-ref-key)
   (inject :initarg :inject :reader secret-ref-inject :initform :env))
  (:documentation
   "Named secret reference. INJECT is :ENV or :FILE. No material slot."))

(defun secret-ref-p (object)
  (typep object 'secret-ref))

(defun make-secret-ref (&key name key (inject :env))
  (check-type name string)
  (check-type key string)
  (unless (member inject '(:env :file))
    (error 'runtime-error
           :message (format nil "secret-ref inject must be :env or :file, got ~s"
                            inject)))
  (make-instance 'secret-ref :name name :key key :inject inject))

(defun %coerce-secret-ref (item)
  (etypecase item
    (secret-ref item)
    (cons (apply #'make-secret-ref item))))

;;; --- workspace / task spec --------------------------------------------------

(defclass runtime-workspace-spec ()
  ((name :initarg :name :reader runtime-workspace-spec-name)
   (path :initarg :path :reader runtime-workspace-spec-path :initform nil)
   (git :initarg :git :reader runtime-workspace-spec-git :initform nil)
   (mcp :initarg :mcp :reader runtime-workspace-spec-mcp :initform nil)
   (skills :initarg :skills :reader runtime-workspace-spec-skills :initform nil)
   (goal :initarg :goal :reader runtime-workspace-spec-goal :initform nil))
  (:documentation
   "Workspace layout. GIT is a list of plists (:REPO :BRANCH :NAME).
GOAL is a setup hint only — backends must not auto-run an agent."))

(defun runtime-workspace-spec-p (object)
  (typep object 'runtime-workspace-spec))

(defun make-runtime-workspace-spec (&key name path git mcp skills goal)
  (check-type name string)
  (when path (check-type path string))
  (check-type git list)
  (make-instance 'runtime-workspace-spec
                 :name name
                 :path path
                 :git (mapcar #'copy-list git)
                 :mcp mcp
                 :skills skills
                 :goal goal))

(defun %coerce-workspace (item)
  (etypecase item
    (runtime-workspace-spec item)
    (cons (apply #'make-runtime-workspace-spec item))))

(defclass runtime-task-spec ()
  ((name :initarg :name :reader runtime-task-spec-name)
   (image :initarg :image :reader runtime-task-spec-image :initform nil)
   (command :initarg :command :reader runtime-task-spec-command :initform nil)
   (workspaces :initarg :workspaces :reader runtime-task-spec-workspaces
               :initform nil)
   (network :initarg :network :reader runtime-task-spec-network :initform nil)
   (resources :initarg :resources :reader runtime-task-spec-resources
              :initform nil)
   (secrets :initarg :secrets :reader runtime-task-spec-secrets :initform nil)
   (debug :initarg :debug :reader runtime-task-spec-debug :initform nil))
  (:documentation
   "Long-lived task. RESOURCES is a plist (:CPU :MEMORY).
SECRETS is a list of SECRET-REF. DEBUG gates EXEC-IN-TASK."))

(defun runtime-task-spec-p (object)
  (typep object 'runtime-task-spec))

(defun make-runtime-task-spec (&key name image command workspaces network
                                 resources secrets debug)
  (when name (check-type name string))
  (when command (check-type command list))
  (when resources (check-type resources list))
  (make-instance 'runtime-task-spec
                 :name name
                 :image image
                 :command command
                 :workspaces (mapcar #'%coerce-workspace workspaces)
                 :network (%coerce-network network)
                 :resources (copy-list resources)
                 :secrets (mapcar #'%coerce-secret-ref secrets)
                 :debug debug))

(defun coerce-runtime-task-spec (spec)
  "Accept a RUNTIME-TASK-SPEC or keyword plist."
  (etypecase spec
    (runtime-task-spec spec)
    (null (make-runtime-task-spec))
    (cons
     (if (keywordp (car spec))
         (apply #'make-runtime-task-spec spec)
         (error 'runtime-error
                :message (format nil "cannot coerce task spec: ~s" spec))))))

;;; --- status / conditions ----------------------------------------------------

(defclass runtime-condition ()
  ((type :initarg :type :reader runtime-condition-type)
   (status :initarg :status :reader runtime-condition-status :initform nil)
   (reason :initarg :reason :reader runtime-condition-reason :initform nil))
  (:documentation
   "TYPE is :WORKSPACE-READY, :GATEWAY-READY, or :READY.
STATUS is T or NIL. REASON is a keyword such as :TASK-SUSPENDED."))

(defun runtime-condition-p (object)
  (typep object 'runtime-condition))

(defun make-runtime-condition (&key type (status nil) reason)
  (check-type type keyword)
  (make-instance 'runtime-condition :type type :status status :reason reason))

(defclass runtime-status ()
  ((phase :initarg :phase :reader runtime-status-phase)
   (conditions :initarg :conditions :reader runtime-status-conditions
               :initform nil)
   (snapshot-ref :initarg :snapshot-ref :reader runtime-status-snapshot-ref
                 :initform nil)
   (worker-id :initarg :worker-id :reader runtime-status-worker-id
              :initform nil)))

(defun runtime-status-p (object)
  (typep object 'runtime-status))

(defun make-runtime-status (&key phase conditions snapshot-ref worker-id)
  (unless (member phase *runtime-phases*)
    (error 'runtime-error
           :phase phase
           :message (format nil "unknown phase ~s" phase)))
  (check-type conditions list)
  (dolist (c conditions)
    (check-type c runtime-condition))
  (make-instance 'runtime-status
                 :phase phase
                 :conditions (copy-list conditions)
                 :snapshot-ref snapshot-ref
                 :worker-id worker-id))

(defun find-runtime-condition (status type)
  "Return the RUNTIME-CONDITION of TYPE on STATUS, or NIL."
  (check-type status runtime-status)
  (find type (runtime-status-conditions status) :key #'runtime-condition-type))

(defun %ready-conditions (&key (ready t) reason)
  (list (make-runtime-condition :type :workspace-ready :status ready)
        (make-runtime-condition :type :gateway-ready :status ready)
        (make-runtime-condition :type :ready :status ready :reason reason)))

;;; --- generic functions ------------------------------------------------------

(defgeneric apply-task (backend spec)
  (:documentation
   "Materialize SPEC on BACKEND → RUNTIME-STATUS (phase :RUNNING when ready).
Restarts: USE-VALUE, ABORT, RETRY."))

(defgeneric describe-task (backend id)
  (:documentation "Current RUNTIME-STATUS for ID."))

(defgeneric watch-task (backend id)
  (:documentation
   "Observe ID. May return the current RUNTIME-STATUS; streaming is optional."))

(defgeneric suspend-task (backend id)
  (:documentation
   "Suspend ID. Ready is false with reason :TASK-SUSPENDED; phase :SUSPENDED."))

(defgeneric resume-task (backend id)
  (:documentation
   "Resume ID. Phase :RUNNING, Ready true. Memory backend restores the file map."))

(defgeneric delete-task (backend id)
  (:documentation "Terminate and forget ID. → RUNTIME-STATUS phase :TERMINATING."))

(defgeneric exec-in-task (backend id argv)
  (:documentation
   "Debug-only exec of ARGV (list of strings) inside ID.
Signals RUNTIME-DENIED when the task spec did not set :DEBUG T."))

(defmethod apply-task :around (backend spec)
  (tagbody
   retry
     (return-from apply-task
       (restart-case (call-next-method backend spec)
         (use-value (value)
           :report "Use a supplied runtime-status"
           :interactive (lambda ()
                          (format *query-io* "Status: ")
                          (force-output *query-io*)
                          (list (read *query-io*)))
           value)
         (abort ()
           :report "Abort apply-task"
           nil)
         (retry ()
           :report "Retry apply-task"
           (go retry))))))

(defmethod apply-task (backend spec)
  (declare (ignore spec))
  (error 'runtime-error
         :message (format nil "not a runtime backend: ~s" backend)))

(defmethod describe-task (backend id)
  (declare (ignore id))
  (error 'runtime-error
         :message (format nil "not a runtime backend: ~s" backend)))

(defmethod watch-task (backend id)
  (describe-task backend id))

(defmethod suspend-task (backend id)
  (declare (ignore id))
  (error 'runtime-error
         :message (format nil "not a runtime backend: ~s" backend)))

(defmethod resume-task (backend id)
  (declare (ignore id))
  (error 'runtime-error
         :message (format nil "not a runtime backend: ~s" backend)))

(defmethod delete-task (backend id)
  (declare (ignore id))
  (error 'runtime-error
         :message (format nil "not a runtime backend: ~s" backend)))

(defmethod exec-in-task (backend id argv)
  (declare (ignore id argv))
  (error 'runtime-error
         :message (format nil "not a runtime backend: ~s" backend)))
