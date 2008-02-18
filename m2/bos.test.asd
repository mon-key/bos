(in-package :cl-user)

(asdf:defsystem :bos.test
  :description "BOS Online-System test-suite"
  :depends-on (:bos.web :fiveam)
  :components ((:file "packages-test")
	       (:file "test-suites" :depends-on ("packages-test"))
	       (:file "test-fixtures" :depends-on ("packages-test"))
	       (:file "allocation-test" :depends-on ("test-suites" "test-fixtures"))	       
	       ;; (:file "utils" :depends-on ("config"))
	       ))
