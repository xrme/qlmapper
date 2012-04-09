;;;; qlmapper.lisp

(in-package #:qlmapper)

;;; "qlmapper" goes here. Hacks and glory await!

(defvar *sbcl-program* sb-ext:*runtime-pathname*)

(defun eval-defvar-forms (environment-pairs)
  (loop for (name value) on environment-pairs by #'cddr
        for sym = (format nil "cl-user::~A" name)
        collect "--eval"
        collect (format nil "(defvar ~A (sb-posix:getenv ~S))" sym name)
        collect "--eval"
        collect (format nil "(export '~A '#:cl-user)" sym)))

(defun environment-list (environment-pairs)
  (loop for (name value) on environment-pairs by #'cddr
        collect (format nil "~A=~A" name value)))

(defun flatlist (&rest args)
  (alexandria:flatten args))

(defun run-sbcl (&key file environment-pairs evals)
  (run-program (native-namestring (pathname *sbcl-program*))
               (flatlist "--noinform"
                         "--non-interactive"
                         "--no-userinit"
                         "--no-sysinit"
                         "--load" (native-namestring
                                   (ql-setup:qmerge "setup.lisp"))
                         (eval-defvar-forms environment-pairs)
                         "--eval"
                         (format nil  "(setf cl:*default-pathname-defaults* ~
                                       #p~S)"
                                 (native-namestring *default-pathname-defaults*))
                         (mapcar (lambda (eval)
                                   (list "--eval" eval))
                                 evals)
                        "--load" (native-namestring
                                   (truename file)))
               :environment (append (environment-list environment-pairs)
                                    (sb-ext:posix-environ))
               :output *standard-output*))


(defgeneric base-directory (object)
  (:method ((release ql-dist:release))
    (ql-dist:base-directory release))
  (:method ((system ql-dist:system))
    (base-directory (ql-dist:release system))))

(defun map-objects (file
                    &key dist-name function (filter 'identity) evals)
  (unless (probe-file file)
    (error "~S does not exist" file))
  (let ((dist (ql-dist:find-dist dist-name)))
    (unless dist
      (error "~S does not name any known dist" dist-name))
    (let ((objects (funcall function dist)))
      (dolist (object objects)
        (let ((name (ql-dist:name object)))
          (when (funcall filter name)
            (ql-dist:ensure-installed object)
            (let ((*default-pathname-defaults*
                   (base-directory object)))
              (run-sbcl :file file
                        :environment-pairs (list "*qlmapper-object-name*"
                                                 name)
                        :evals evals))))))))

(defun map-releases (file &key (dist-name "quicklisp") (filter 'identity))
  "For each release in a dist (defaults to the \"quicklisp\" dist),
  start an independent SBCL process and load FILE with the variable
  CL-USER:*QLMAPPER-OBJECT-NAME* bound to the release's name."
  (map-objects file
               :dist-name dist-name
               :function #'ql-dist:provided-releases
               :filter filter))

(defun map-systems (file &key (dist-name "quicklisp") (filter 'identity))
  "For each system in a dist (defaults to the \"quicklisp\" dist),
  start an independent SBCL process and load FILE with the variable
  CL-USER:*QLMAPPER-OBJECT-NAME* bound to the system's name."
  (map-objects file
               :dist-name dist-name
               :function #'ql-dist:provided-systems
               :filter filter))

(defun map-loaded-systems (file &key (dist-name "quicklisp") (filter 'identity))
  "For each system in a dist (defaults to the \"quicklisp\" dist),
  start an independent SBCL process and load FILE with the variable
  CL-USER:*QLMAPPER-OBJECT-NAME* bound to the system's name."
  (map-objects file
               :dist-name dist-name
               :function #'ql-dist:provided-systems
               :filter filter
               :evals '("(ql:quickload cl-user:*qlmapper-object-name*)")))
