(in-package #:agent-runtime-protocol)

;;; In-tree fake backend. Tasks live in a hash-table. Workspaces are
;;; directories under ROOT (default: a unique dir in
;;; UIOP:TEMPORARY-DIRECTORY). Git entries become empty dirs + a marker
;;; file. Suspend snapshots path→string; resume restores that map.

(defclass memory-runtime-backend (runtime-backend)
  ((root :initarg :root :reader memory-runtime-backend-root)
   (tasks :initform (make-hash-table :test 'equal)
          :reader memory-runtime-backend-tasks)))

(defclass memory-runtime-task ()
  ((id :initarg :id :accessor memory-runtime-task-id)
   (spec :initarg :spec :accessor memory-runtime-task-spec)
   (status :initarg :status :accessor memory-runtime-task-status)
   (root :initarg :root :accessor memory-runtime-task-root)
   (files :initarg :files :accessor memory-runtime-task-files
          :initform (make-hash-table :test 'equal))))

(defun %unique-temp-root ()
  (loop
    (let ((path (merge-pathnames
                 (format nil "agent-runtime-~a/" (random (expt 36 8)))
                 (uiop:ensure-directory-pathname (uiop:temporary-directory)))))
      (unless (probe-file path)
        (return (uiop:ensure-directory-pathname path))))))

(defun make-memory-runtime-backend (&key root)
  (let ((root (uiop:ensure-directory-pathname
               (or root (%unique-temp-root)))))
    (ensure-directories-exist root)
    (make-instance 'memory-runtime-backend :root root)))

(defun use-memory-runtime-backend (&rest args &key &allow-other-keys)
  (setf *runtime-backend* (apply #'make-memory-runtime-backend args)))

(defun %task-table (backend)
  (memory-runtime-backend-tasks backend))

(defun %get-task (backend id)
  (or (gethash id (%task-table backend))
      (error 'runtime-not-found
             :id id
             :message (format nil "unknown task ~s" id))))

(defun %task-phase (task)
  (runtime-status-phase (memory-runtime-task-status task)))

(defun %ensure-phase (task expected)
  (let* ((phase (%task-phase task))
         (ok (if (listp expected)
                 (member phase expected)
                 (eq phase expected))))
    (unless ok
      (error 'runtime-invalid-phase
             :id (memory-runtime-task-id task)
             :phase phase
             :expected expected
             :message (format nil "task ~s is ~s, expected ~s"
                              (memory-runtime-task-id task) phase expected)))
    task))

(defun %safe-name (name)
  (substitute #\- #\/ (string name)))

(defun %git-dirname (entry)
  (let* ((given (getf entry :name))
         (repo (getf entry :repo))
         (base (or given
                   (when repo
                     (let* ((s (string-right-trim "/" (string repo)))
                            (s (if (and (> (length s) 4)
                                        (string-equal ".git" s :start2 (- (length s) 4)))
                                   (subseq s 0 (- (length s) 4))
                                   s))
                            (slash (position #\/ s :from-end t)))
                       (if slash (subseq s (1+ slash)) s)))
                   "repo")))
    (%safe-name base)))

(defun %workspace-rel (ws)
  (%safe-name (or (runtime-workspace-spec-path ws)
                  (runtime-workspace-spec-name ws)
                  "workspace")))

(defun %write-marker (pathname)
  (ensure-directories-exist pathname)
  (with-open-file (out pathname :direction :output :if-exists :supersede
                       :if-does-not-exist :create)
    (write-string "agent-runtime-protocol" out))
  pathname)

(defun %materialize-workspace (task-root ws)
  (let* ((rel (%workspace-rel ws))
         (ws-dir (uiop:ensure-directory-pathname
                  (merge-pathnames (uiop:parse-unix-namestring
                                    (format nil "~a/" rel))
                                   task-root))))
    (ensure-directories-exist ws-dir)
    (%write-marker (merge-pathnames ".runtime-workspace" ws-dir))
    (dolist (entry (runtime-workspace-spec-git ws))
      (let ((git-dir (uiop:ensure-directory-pathname
                      (merge-pathnames (uiop:parse-unix-namestring
                                        (format nil "~a/" (%git-dirname entry)))
                                       ws-dir))))
        (ensure-directories-exist git-dir)
        (%write-marker (merge-pathnames ".runtime-git" git-dir))))
    ws-dir))

(defun %materialize-spec (task-root spec)
  (ensure-directories-exist task-root)
  (%write-marker (merge-pathnames ".runtime-task" task-root))
  (let ((workspaces (runtime-task-spec-workspaces spec)))
    (if workspaces
        (dolist (ws workspaces)
          (%materialize-workspace task-root ws))
        (ensure-directories-exist task-root)))
  task-root)

(defun %list-files (root)
  (let ((files nil)
        (root (uiop:ensure-directory-pathname root)))
    (when (uiop:directory-exists-p root)
      (uiop:collect-sub*directories
       root
       (constantly t)
       (constantly t)
       (lambda (dir)
         (dolist (f (uiop:directory-files dir))
           (push f files)))))
    files))

(defun %snapshot-files (root)
  (let ((table (make-hash-table :test 'equal))
        (root (uiop:ensure-directory-pathname root)))
    (dolist (file (%list-files root))
      (setf (gethash (enough-namestring file root) table)
            (uiop:read-file-string file)))
    table))

(defun %wipe-files (root)
  (dolist (file (%list-files root))
    (ignore-errors (delete-file file))))

(defun %restore-files (root table)
  (let ((root (uiop:ensure-directory-pathname root)))
    (ensure-directories-exist root)
    (maphash (lambda (rel contents)
               (let ((path (merge-pathnames (uiop:parse-unix-namestring rel)
                                            root)))
                 (ensure-directories-exist path)
                 (with-open-file (out path :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create)
                   (write-string contents out))))
             table)
    root))

(defun %cleanup-root (root)
  (when (and root (uiop:directory-exists-p root))
    (uiop:delete-directory-tree (uiop:ensure-directory-pathname root)
                                :validate t
                                :if-does-not-exist :ignore)))

(defun memory-runtime-workspace-path (backend id &optional workspace-name)
  "Directory for ID, or the named workspace under that task."
  (let* ((task (%get-task backend id))
         (root (uiop:ensure-directory-pathname (memory-runtime-task-root task))))
    (if workspace-name
        (uiop:ensure-directory-pathname
         (merge-pathnames (uiop:parse-unix-namestring
                           (format nil "~a/" (%safe-name workspace-name)))
                          root))
        root)))

(defun %require-name (spec)
  (let ((name (runtime-task-spec-name spec)))
    (unless (and name (plusp (length name)))
      (error 'runtime-error
             :message "runtime-task-spec needs :name"))
    name))

(defmethod apply-task ((backend memory-runtime-backend) spec)
  (let* ((spec (coerce-runtime-task-spec spec))
         (id (%require-name spec))
         (table (%task-table backend)))
    (when (gethash id table)
      (let ((existing (gethash id table)))
        (error 'runtime-invalid-phase
               :id id
               :phase (%task-phase existing)
               :expected :pending
               :message (format nil "task ~s already exists" id))))
    (let* ((task-root (uiop:ensure-directory-pathname
                       (merge-pathnames (uiop:parse-unix-namestring
                                         (format nil "~a/" (%safe-name id)))
                                        (memory-runtime-backend-root backend))))
           (status (make-runtime-status
                    :phase :running
                    :conditions (%ready-conditions :ready t)
                    :worker-id "memory"))
           (task (make-instance 'memory-runtime-task
                                :id id
                                :spec spec
                                :status status
                                :root task-root)))
      (%materialize-spec task-root spec)
      (setf (gethash id table) task)
      status)))

(defmethod describe-task ((backend memory-runtime-backend) id)
  (memory-runtime-task-status (%get-task backend id)))

(defmethod suspend-task ((backend memory-runtime-backend) id)
  (let ((task (%get-task backend id)))
    (%ensure-phase task :running)
    (let ((files (%snapshot-files (memory-runtime-task-root task))))
      (setf (memory-runtime-task-files task) files)
      (%wipe-files (memory-runtime-task-root task))
      (let ((status (make-runtime-status
                     :phase :suspended
                     :conditions (list (make-runtime-condition
                                        :type :workspace-ready :status t)
                                       (make-runtime-condition
                                        :type :gateway-ready :status t)
                                       (make-runtime-condition
                                        :type :ready :status nil
                                        :reason :task-suspended))
                     :snapshot-ref (format nil "memory:~a" id)
                     :worker-id "memory")))
        (setf (memory-runtime-task-status task) status)
        status))))

(defmethod resume-task ((backend memory-runtime-backend) id)
  (let ((task (%get-task backend id)))
    (%ensure-phase task :suspended)
    (%restore-files (memory-runtime-task-root task)
                    (memory-runtime-task-files task))
    (let ((status (make-runtime-status
                   :phase :running
                   :conditions (%ready-conditions :ready t)
                   :worker-id "memory")))
      (setf (memory-runtime-task-status task) status)
      status)))

(defmethod delete-task ((backend memory-runtime-backend) id)
  (let ((task (%get-task backend id)))
    (let ((status (make-runtime-status
                   :phase :terminating
                   :conditions (runtime-status-conditions
                                (memory-runtime-task-status task))
                   :worker-id "memory")))
      (%cleanup-root (memory-runtime-task-root task))
      (remhash id (%task-table backend))
      status)))

(defmethod exec-in-task ((backend memory-runtime-backend) id argv)
  (check-type argv list)
  (let* ((task (%get-task backend id))
         (spec (memory-runtime-task-spec task)))
    (unless (runtime-task-spec-debug spec)
      (error 'runtime-denied
             :id id
             :policy :debug
             :message "exec-in-task requires :debug t"))
    (%ensure-phase task :running)
    (list :exit-code 0 :argv (mapcar (lambda (x)
                                       (if (stringp x) x (princ-to-string x)))
                                     argv))))
