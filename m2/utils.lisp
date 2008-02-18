(in-package :bos.m2)

(enable-interpol-syntax)

(defun escape-nl (string)
  (if string
      (regex-replace-all #?r"[\n\r]+" string #?"<br />")
      ""))

(defun random-elt (choices)
  (when choices
    (elt choices (random (length choices)))))