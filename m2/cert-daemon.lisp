(in-package :bos.m2.cert-generator)

(defun run-tool (program &optional program-args &rest args)
  (let* ((process (apply #'run-program program program-args :output :stream args))
         (error-message (unless (zerop (process-exit-code process))
                          (with-output-to-string (*standard-output*)
                            (with-open-stream (output-stream (process-output process))
                              (princ (read-line output-stream)))))))
    (process-close process)
    (unless (zerop (process-exit-code process))
      (error "Error executing ~A - Exit code ~D~%Error message: ~A"
             (format nil "\"~A~{ ~A~}\"" program program-args) (process-exit-code process) error-message))))

(defun fill-form (fdf-pathname pdf-pathname output-pathname)
  (handler-case
      (progn
        (ignore-errors (run-tool "recode" (list "utf-8..latin-1" (unix-namestring fdf-pathname))))
        (cond
          ((unix-namestring pdf-pathname)
           (run-tool "pdftk" (list (unix-namestring pdf-pathname)
                                   "fill_form" (unix-namestring fdf-pathname)
                                   "output" (namestring output-pathname)
                                   "flatten"))
           (format t "; generated ~A~%" output-pathname))
          (t
           (warn "Warning, stray FDF file ~A deleted, no such contract exists" fdf-pathname)))
        (delete-file fdf-pathname))
    (error (e)
      (warn "While filling form ~A with ~A:~%~A" pdf-pathname fdf-pathname e))))

(defun fill-forms (directory template-pathname)
  (dolist (fdf-pathname (remove "fdf" (directory directory)
				:test (complement #'string-equal)
				:key #'pathname-type))
    (destructuring-bind (id &optional (country "en")) (split "-" (pathname-name fdf-pathname))
      (let ((language-specific-template-pathname (merge-pathnames (make-pathname :name (format nil "~A-~A" (pathname-name template-pathname) country))
                                                                  template-pathname))
            (output-pathname (merge-pathnames (make-pathname :name id :type "pdf") fdf-pathname)))
        (fill-form fdf-pathname (if (probe-file language-specific-template-pathname)
                                    language-specific-template-pathname
                                    template-pathname)
                   output-pathname)))))

(defun generate-certs ()
  (fill-forms *cert-mail-directory* *cert-mail-template*)
  (fill-forms *cert-download-directory* *cert-download-template*)
  (fill-forms *receipt-mail-directory* *receipt-mail-template*)
  (fill-forms *receipt-download-directory* *receipt-download-template*))

(defun cert-daemon ()
  (ensure-directories-exist *cert-mail-directory*)
  (ensure-directories-exist *cert-download-directory*)
  (loop
     (generate-certs)
     (sleep *cert-daemon-poll-seconds*)))