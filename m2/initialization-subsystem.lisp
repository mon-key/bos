(in-package :bos.m2)

;;; store-transient-init-functions
;;;
;;; Allows for registering transient init functions that
;;; will be called after each restore of m2-store

(defvar *store-transient-init-functions* nil)
(defvar *store-transient-init-constraints* nil)

(defun register-store-transient-init-function (init-function &rest dependencies)
  "Register INIT-FUNCTION (a function-name) to be called after
each restore of m2-store.  Optionally, names of other
init-functions can be specified as DEPENDENCIES. The specified
INIT-FUNCTION will only be called after all of its DEPENDENCIES
have been called."
  (labels ((ignorant-tie-breaker (choices reverse-partial-solution)
             (declare (ignore reverse-partial-solution))         
             ;; we dont care about making any particular choice here -
             ;; this would be different for computing the class
             ;; precedence list, for which the topological-sort used here
             ;; was originally intended
             (first choices))
           (build-constraints ()
             (loop for dependency in dependencies
                collect (cons dependency init-function))))
    (check-type init-function symbol)
    (dolist (dependency dependencies)
      (check-type dependency symbol))    
    (let (new-store-transient-init-functions
          new-store-transient-init-constraints)
      (let ((constraints (build-constraints))
            ;; dont know yet whether we have a circular dependency - so
            ;; we want to be able to abort without changes
            (*store-transient-init-functions* *store-transient-init-functions*)
            (*store-transient-init-constraints* *store-transient-init-constraints*))      
        (pushnew init-function *store-transient-init-functions*)
        (dolist (dependency dependencies)
          (pushnew dependency *store-transient-init-functions*))
        (dolist (constraint constraints)
          (pushnew constraint *store-transient-init-constraints* :test #'equal))
        (setq new-store-transient-init-functions
              (topological-sort *store-transient-init-functions*
                                *store-transient-init-constraints*
                                #'ignorant-tie-breaker)
              new-store-transient-init-constraints
              *store-transient-init-constraints*))
      (setq *store-transient-init-functions*
            new-store-transient-init-functions
            *store-transient-init-constraints*
            new-store-transient-init-constraints))))

(defun invoke-store-transient-init-functions ()
  (dolist (function-name *store-transient-init-functions*)
    (with-simple-restart (skip-init-function "Skip transient-init-function ~A"
                                             function-name)
      (funcall function-name))))

;;; initialization-subsystem
(defclass initialization-subsystem ()
  ())

(defmethod bknr.datastore::restore-subsystem (store (subsystem initialization-subsystem)
                                              &key until)
  (declare (ignore until))
  (bos.m2::invoke-store-transient-init-functions))

(defmethod bknr.datastore::snapshot-subsystem (store (subsystem initialization-subsystem))
  )

