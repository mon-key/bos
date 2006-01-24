(in-package :bos.m2)

;;;; M2-STORE

(defvar *m2-store* nil)

(defclass m2-store (mp-store)
  ((tile-index :reader m2-store-tile-index)))

(defmethod initialize-instance :before ((store m2-store) &key &allow-other-keys)
  (when *m2-store*
    (warn "reinitializing m2-store object"))
  (setq *m2-store* store)
  (setf (slot-value store 'tile-index)
	(indexed-class-index-named (find-class 'm2) 'm2-index)))

(defun get-map-tile (x y)
  (get-tile (m2-store-tile-index *m2-store*) x y))

(defun ensure-map-tile (x y)
  (ensure-tile (m2-store-tile-index *m2-store*) x y))

;;;; M2

;;; Exportierte Funktionen:
;;;
;;; M2-CONTRACT (m2) => contract or NIL
;;; M2-NUM (m2) => integer
;;; M2-PRINTABLE (m2) => string
;;; M2-X (m2) => integer
;;; M2-Y (m2) => integer
;;; M2-UTM-X (m2) => double-float
;;; M2-UTM-y (m2) => double-float
;;;
;;; GET-M2 (x y) => m2 or NIL
;;; ENSURE-M2 (x y) => m2
;;; GET-M2-WITH-NUM (sqm-num) => m2 or nil
;;; ENSURE-M2-WITH-NUM (sqm-num) => m2

(define-persistent-class m2 ()
  ((x :read)
   (y :read)
   (contract :update :relaxed-object-reference t))
  (:default-initargs :contract nil)
  (:class-indices (m2-index :index-type tiled-index
			    :slots (x y)
			    :index-reader m2-at
			    :index-initargs (:width +width+ :height +width+ :tile-size +m2tile-width+ :tile-class 'image-tile))))

(defmethod print-object ((object m2) stream)
  (print-unreadable-object (object stream :type t :identity nil)
    (format stream "at (~D,~D), ~A"
            (m2-x object)
            (m2-y object)
            (if (m2-contract object) "sold" "free"))))

(defun get-m2 (&rest coords)
  (m2-at coords))

(defun ensure-m2 (&rest coords)
  (or (m2-at coords)
      (destructuring-bind (x y) coords
	(make-instance 'm2 :x x :y y))))

(defmethod get-m2-with-num ((num integer))
  (multiple-value-bind (y x) (truncate num +width+)
    (get-m2 x y)))

(defmethod get-m2-with-num ((num string))
  (get-m2-with-num (parse-integer num :radix 36)))

(defmethod ensure-m2-with-num ((num integer))
  (multiple-value-bind (y x) (truncate num +width+)
    (ensure-m2 x y)))

(defmethod ensure-m2-with-num ((num string))
  (ensure-m2-with-num (parse-integer num :radix 36)))

(defun m2-num (m2)
  "Fortlaufende Quadratmeternummer in row-major-order."
  (+ (* (m2-y m2) +width+) (m2-x m2)))

(defun m2-num-string (m2)
  "Quadratmeternummer im druckbaren Format (Radix 36, 6 Zeichen lang)"
  (format nil "~36,6,'0R" (m2-num m2)))

;; UTM laeuft von links nach rechts und von UNTEN NACH OBEN.
(defun m2-utm-x (m2) (+ +nw-utm-x+ (m2-x m2)))
(defun m2-utm-y (m2) (- +nw-utm-y+ (m2-y m2)))

(defmethod m2-num-to-utm ((num integer))
  (multiple-value-bind (y x) (truncate num +width+)
    (+ +nw-utm-x+ x)
    (- +nw-utm-y+ y)))

(defmethod m2-num-to-utm ((num string))
  (m2-num-to-utm (parse-integer num :radix 36)))

(defmethod m2-allocation-area ((m2 m2))
  (find-if #'(lambda (allocation-area) (point-in-polygon-p (m2-x m2) (m2-y m2) (allocation-area-vertices allocation-area)))
	   (class-instances 'allocation-area)))

;;;; SPONSOR

;;; Exportierte Funktionen:
;;;
;;; MAKE-SPONSOR (&rest initargs) => sponsor
;;; (Automatisch Zuweisung eines Login-Namens.)
;;;
;;; SPONSOR-PASSWORD-QUESTION (sponsor) => string
;;; SPONSOR-PASSWORD-ANSWER (sponsor) => string
;;; SPONSOR-INFO-TEXT (sponsor) => string
;;; SPONSOR-COUNTRY (sponsor) => string
;;; SPONSOR-CONTRACTS (sponsor) => list of contract
;;;
;;; Sowie Funktionen von USER.

(define-persistent-class sponsor (user)
  ((master-code :read          :initform nil)
   (info-text :update	       :initform nil)
   (country :update	       :initform nil)
   (contracts :update          :initform nil))
  (:default-initargs :full-name nil :email nil))

(defun sponsor-p (object)
  (equal (class-of object) (find-class 'sponsor)))

(deftransaction sponsor-set-info-text (sponsor newval)
  (setf (sponsor-info-text sponsor) newval))

(deftransaction sponsor-set-country (sponsor newval)
  (setf (sponsor-country sponsor) newval))

(defvar *sponsor-counter* 0)

(defun make-sponsor (&rest initargs &key login &allow-other-keys)
  (apply #'make-object 'sponsor
         :login (or login (format nil "s-~36R-~36R" (incf *sponsor-counter*) (get-universal-time)))
	 :master-code (mod (+ (get-universal-time) (random 1000000)) 1000000)
         initargs))

(defmethod destroy-object :before ((sponsor sponsor))
  (mapc #'delete-object (sponsor-contracts sponsor)))

(defmethod sponsor-id ((sponsor sponsor))
  (store-object-id sponsor))

;;;; CONTRACT

;;; Exportierte Funktionen:
;;;
;;; MAKE-CONTRACT (sponsor m2s) => contract
;;;
;;; GET-CONTRACT (id) => contract
;;;
;;; CONTRACT-SPONSOR (contract) => sponsor
;;; CONTRACT-PAIDP (contract) => boolean
;;; CONTRACT-DATE (contract) => Universal-Timestamp
;;; CONTRACT-M2S (contract) => list of m2
;;;
;;; CONTRACT-SET-PAIDP (contract newval) => newval

(defvar *claim-colors* '((0 0 128)
			 (0 128 0)
			 (0 128 128)
			 (128 0 0)
			 (128 0 128)
			 (128 128 0)
			 (0 0 255)
			 (0 255 0)
			 (0 255 255)
			 (255 0 0)
			 (255 0 255)
			 (255 255 0)))

(define-persistent-class contract ()
  ((sponsor :read :relaxed-object-reference t)
   (date :read)
   (paidp :update)
   (m2s :read)
   (color :read)
   (cert-issued :read)
   (expires :read :documentation "universal time which specifies the time the contract expires (is deleted) when it has not been paid for" :initform nil))
  (:default-initargs
      :m2s nil
    :color (random-elt *claim-colors*)
    :cert-issued nil
    :expires (+ (get-universal-time) *manual-contract-expiry-time*)))

(defun contract-p (object)
  (equal (class-of object) (find-class 'contract)))

(defmethod initialize-persistent-instance :after ((contract contract))
  (pushnew contract (sponsor-contracts (contract-sponsor contract)))
  (contract-changed contract)
  (dolist (m2 (contract-m2s contract))
    (setf (m2-contract m2) contract)))

(defmethod destroy-object :before ((contract contract))
  (let ((sponsor (contract-sponsor contract)))
    (when sponsor
      (setf (sponsor-contracts sponsor) (remove contract (sponsor-contracts sponsor)))))
  (contract-changed contract)
  (dolist (m2 (contract-m2s contract))
    (setf (m2-contract m2) nil))
  (return-m2s (contract-m2s contract)))

(defun get-contract (id)
  (let ((contract (store-object-with-id id)))
    (prog1
	contract
      (unless (subtypep (type-of contract) 'contract)
	(error "invalid contract id (wrong type) ~A" id)))))

(defmethod contract-changed ((contract contract))
  (mapc #'(lambda (tile) (image-tile-changed tile)) (contract-image-tiles contract)))

(defmethod contract-is-expired ((contract contract))
  (and (contract-expires contract)
       (> (get-universal-time) (contract-expires contract))))

(deftransaction contract-set-paidp (contract newval)
  (contract-changed contract)
  (setf (contract-paidp contract) newval))

(defmethod contract-price ((contract contract))
  (* (length (contract-m2s contract)) +price-per-m2+))

(defmethod contract-download-only-p ((contract contract))
  (< (contract-price contract) *mail-amount*))

(defmethod contract-fdf-pathname ((contract contract))
  (merge-pathnames (make-pathname :name (format nil "~D" (store-object-id contract))
				  :type "fdf")
		   (if (contract-download-only-p contract) *cert-download-directory* *cert-mail-directory*)))

(defmethod contract-pdf-pathname ((contract contract))
  (merge-pathnames (make-pathname :name (format nil "~D" (store-object-id contract))
				  :type "pdf")
		   (if (contract-download-only-p contract)
		       bos.m2::*cert-download-directory*
		       bos.m2::*cert-mail-directory*)))

(defmethod contract-pdf-url ((contract contract))
  (format nil "/~:[~;print-~]certificate/~A" (not (contract-download-only-p contract)) (store-object-id contract)))

(defmethod contract-issue-cert ((contract contract) name &optional address)
  (if (contract-cert-issued contract)
      (warn "can't re-issue cert for ~A" contract)
      (progn
	(make-certificate contract name :address address)
	(unless (contract-download-only-p contract)
	  (mail-certificate-to-office contract address))
	(change-slot-values contract 'cert-issued t))))

(defmethod contract-image-tiles ((contract contract))
  (let (image-tiles)
    (dolist (m2 (contract-m2s contract))
      (pushnew (get-map-tile (m2-x m2) (m2-y m2))
	       image-tiles))
    image-tiles))

(defun tx-make-contract (sponsor m2-count &key date paidp expires)
  (warn "Old tx-make-contract transaction used, contract dates may be wrong")
  (tx-do-make-contract sponsor m2-count :date date :paidp paidp :expires expires))

(deftransaction do-make-contract (sponsor m2-count &key date paidp expires)
  (let ((m2s (find-free-m2s m2-count)))
    (if m2s
	(make-object 'contract
		     :sponsor sponsor
		     :date date
		     :paidp paidp
		     :m2s m2s
		     :expires expires)
	(warn "can't create contract, ~A square meters for ~A could not be allocated" m2-count sponsor))))

(defun make-contract (sponsor m2-count &key (date (get-universal-time)) paidp (expires (+ (get-universal-time) *manual-contract-expiry-time*)))
  (unless (and (integerp m2-count)
	       (plusp m2-count))
    (error "number of square meters must be a positive integer"))
  (do-make-contract sponsor m2-count :date date :paidp paidp :expires expires))

(defun number-of-sold-sqm ()
  (let ((retval 0))
    (dolist (contract (remove-if-not #'contract-paidp (class-instances 'contract)))
      (incf retval (length (contract-m2s contract))))
    retval))

(defun string-safe (string)
  (if string
      (escape-nl (with-output-to-string (s)
		   (net.html.generator::emit-safe s string)))
      ""))

(defun make-m2-javascript (sponsor)
  "Erzeugt das Quadratmeter-Javascript f�r die angegebenen Contracts"
  (with-output-to-string (*standard-output*)
    (let ((paid-contracts (remove nil (sponsor-contracts sponsor) :key #'contract-paidp)))
      (format t "profil = [];~%")
      (format t "qms = [ undefined ];~%")
      (format t "profil['id'] = ~D;~%" (store-object-id sponsor))
      (format t "profil['name'] = ~S;~%" (string-safe (or (user-full-name sponsor) "[anonym]")))
      (format t "profil['country'] = ~S;~%" (or (sponsor-country sponsor) "[unbekannt]"))
      (format t "profil['anzahl'] = ~D;~%" (loop for contract in paid-contracts
								  sum (length (contract-m2s contract))))
      (format t "profil['nachricht'] = '~A';~%" (string-safe (sponsor-info-text sponsor)))
      (loop for contract in paid-contracts
	    for m2s = (sort (copy-list (contract-m2s contract)) #'(lambda (a b) (if (eql (m2-y a) (m2-y b))
										    (< (m2-x a) (m2-x b))
										    (< (m2-y a) (m2-y b)))))
	    do (progn
		 (format t "var qm = [];~%")
		 (format t "qm['x'] = ~D;~%" (m2-x (first (contract-m2s contract))))
		 (format t "qm['y'] = ~D;~%" (m2-y (first (contract-m2s contract))))
		 (format t "qm['datum'] = ~S;~%" (format-date-time (contract-date contract) :show-time nil))
		 (format t "qm['qm_x'] = [0, ~D~{,~D~}];~%"
			 (m2-x (first m2s))
			 (mapcar #'m2-x (cdr m2s)))
		 (format t "qm['qm_y'] = [0, ~D~{,~D~}];~%"
			 (m2-y (first m2s))
			 (mapcar #'m2-y (cdr m2s)))
		 (format t "qms.push(qm);~%"))))))

(defun delete-directory (pathname)
  (when (probe-file pathname)
    ;; XXX Achtung, auf #-cmu folgt das Symlinks.
    (loop for file in (directory pathname #+cmu :truenamep #+cmu nil)
	  when (pathname-name file)
	  do (delete-file file)
	  unless (pathname-name file)
	  do (delete-directory file))
    #+allegro
    ;; Das loescht doch eh schon die unterverzeichnisse mit?
    (excl:delete-directory-and-files pathname)
    #+cmu
    (unix:unix-rmdir (ext:unix-namestring pathname))
    #-(or allegro cmu)
    ...))

(defun reinit (&key delete directory)
  (format t "~&; Startup Quadratmeterdatenbank...~%")
  (force-output)
  (unless directory
    (error ":DIRECTORY parameter not set in m2.rc"))
  (when delete
    (delete-directory directory)
    (assert (not (probe-file directory))))
  (make-instance 'm2-store
		 :directory directory
		 :subsystems (list (make-instance 'store-object-subsystem)
				   (make-instance 'blob-subsystem
						  :n-blobs-per-directory 1000)))
  (format t "~&; Startup der Quadratmeterdatenbank done.~%")
  (force-output))

;; testing

(defun fill-with-random-contracts (&optional percentage)
  (loop for sponsor = (make-sponsor)
	while (and (or (null percentage)
		       (< (allocation-area-percent-used (first (class-instances 'allocation-area))) percentage))
		   (make-contract sponsor
				  (random-elt (cons (1+ (random 300)) '(1 1 1 1 1 5 5 10 10 10 10 10 10 10 10 10 10 10 10 10 30 30 30)))
				  :paidp t))))
