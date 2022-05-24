;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(nyxt:define-and-set-package :nyxt/download-mode
  (:documentation "Mode to manage downloads and the download listing page."))

(export-always 'renderer-download)
(defclass renderer-download ()
  ()
  (:metaclass mixin-class))

(define-class download (renderer-download)
  ((url (error "URL required.")
        :documentation "A string representation of a URL to be shown in the
interface.")
   (status :unloaded
           :export t
           :reader status
           :type (member :unloaded
                         :loading
                         :finished
                         :failed
                         :canceled)
           :documentation "Status of the download.")
   (status-text (make-instance 'user-interface:paragraph)
                :export nil)
   (completion-percentage 0.0
                          :reader t
                          :export t
                          :type float
                          :documentation "A number between 0 and 100
showing the percentage a download is complete.")
   (bytes-downloaded "-"
                     :reader t
                     :export t
                     :documentation "The number of bytes downloaded.")
   (bytes-text (make-instance 'user-interface:paragraph)
               :export nil
               :documentation "The interface element showing how many bytes have
been downloaded.")
   (destination-path #p""
                     :reader t
                     :export t
                     :type pathname
                     :documentation "Where the file will be downloaded to
disk.")
   (cancel-function nil
                    :reader t
                    :export t
                    :type (or null function)
                    :documentation "The function to call when
cancelling a download. This can be set by the download engine.")
   (cancel-button (make-instance 'user-interface:button
                                 :text "✕"
                                 :action (ps:ps (nyxt/ps:lisp-eval '(echo "Can't cancel download."))))
                  :export nil
                  :documentation "The download is referenced by its
URL. The URL for this button is therefore encoded as a funcall to
cancel-download with an argument of the URL to cancel.")
   (open-button (make-instance 'user-interface:button
                               :text "🗁"
                               :action (ps:ps (nyxt/ps:lisp-eval '(echo "Can't open file, file path unknown."))))
                :export nil
                :documentation "The file name to open is encoded
within the button's URL when the destinaton path is set.")
   (progress-text (make-instance 'user-interface:paragraph)
                  :export nil)
   (progress (make-instance 'user-interface:progress-bar)
             :export nil))
  (:accessor-name-transformer (class*:make-name-transformer name))
  (:export-accessor-names-p t)
  (:export-class-name-p t)
  (:documentation "This class is used to represent a download within
the *Downloads* buffer. The browser class contains a list of these
download objects: `downloads'."))

(defun cancel-download (url)
  "This function is called by the cancel-button with an argument of
the URL. It will search the URLs of all the existing downloads, if it
finds it, it will invoke its cancel-function."
  (alex:when-let ((download (find url (downloads *browser*) :key #'url :test #'equal)))
    (funcall (cancel-function download))
    (echo "Download cancelled: ~a." url)))

(defmethod (setf cancel-function) (cancel-function (download download))
  (setf (slot-value download 'cancel-function) cancel-function)
  (setf (user-interface:action (cancel-button download))
        (ps:ps (nyxt/ps:lisp-eval `(cancel-download ,(url download))))))

(defmethod (setf status) (value (download download))
  (setf (slot-value download 'status) value)
  (setf (user-interface:text (status-text download))
        (format nil "Status: ~(~a~)." value)))

(defmethod (setf completion-percentage) (percentage (download download))
  (setf (slot-value download 'completion-percentage) percentage)
  (setf (user-interface:percentage (progress download))
        (completion-percentage download))
  (setf (user-interface:text (progress-text download))
        (format nil "Completion: ~,2f%" (completion-percentage download))))

(defmethod (setf bytes-downloaded) (bytes (download download))
  (setf (slot-value download 'bytes-downloaded) bytes)
  (setf (user-interface:text (bytes-text download))
        (format nil "Bytes downloaded: ~a" (bytes-downloaded download))))

(defmethod (setf destination-path) (path (download download))
  (setf (slot-value download 'destination-path) path)
  (setf (user-interface:action (open-button download))
        (ps:ps (nyxt/ps:lisp-eval `(nyxt/file-manager-mode:default-open-file-function ,path)))))

(defmethod connect ((download download) buffer)
  "Connect the user-interface objects within the download to the
buffer. This allows the user-interface objects to update their
appearance in the buffer when they are setf'd."
  (user-interface:connect (status-text download) buffer)
  (user-interface:connect (progress-text download) buffer)
  (user-interface:connect (bytes-text download) buffer)
  (user-interface:connect (open-button download) buffer)
  (user-interface:connect (cancel-button download) buffer)
  (user-interface:connect (progress download) buffer))

;; TODO: Move to separate package
(define-mode download-mode ()
  "Display list of downloads."
  ((rememberable-p nil)
   (style
       (theme:themed-css (theme *browser*)
         (".download"
          :margin-top "10px"
          :padding-left "5px"
          :background-color theme:background
          :color theme:text
          :brightness "80%"
          :border-radius "3px")
         (".download-url"
          :overflow "auto"
          :white-space "nowrap")
         (".download-url a"
          :font-size "small"
          :color theme:text)
         (".status p"
          :display "inline-block"
          :margin-right "10px")
         (".progress-bar-container"
          :height "20px"
          :width "100%")
         (".progress-bar-base"
          :height "100%"
          :background-color theme:secondary)
         (".progress-bar-fill"
          :height "100%"
          :background-color theme:tertiary))))
  (:toggler-command-p nil))


(define-internal-page-command-global list-downloads ()
    (buffer "*Downloads*" 'download-mode)
  "Display a buffer listing all downloads.
We iterate through the browser's downloads to draw every single
download."
  (spinneret:with-html-string
    (:style (style (find-submode 'download-mode)))
    (:h1 "Downloads")
    (:hr)
    (:div
     (loop for download in (downloads *browser*)
           for url = (url download)
           for status-text = (status-text download)
           for progress-text = (progress-text download)
           for bytes-text = (bytes-text download)
           for progress = (progress download)
           for open-button = (open-button download)
           for cancel-button = (cancel-button download)
           do (connect download buffer)
           collect
           (:div :class "download"
                 (:p :class "download-buttons"
                     ;; TODO: Disable the buttons when download status is failed / canceled.
                     (:raw (user-interface:object-string cancel-button))
                     (:raw (user-interface:object-string open-button)))
                 (:p :class "download-url" (:a :href url url))
                 (:div :class "progress-bar-container"
                       (:raw (user-interface:object-string progress)))
                 (:div :class "status"
                       (:raw (user-interface:object-string progress-text))
                       (:raw (user-interface:object-string bytes-text))
                       (:raw (user-interface:object-string status-text))))))))


(defun download-watch (download-render download-object)
  "Update the *Downloads* buffer.
This function is meant to be run in the background. There is a
potential thread starvation issue if one thread consumes all
messages. If in practice this becomes a problem, we should poll on
each thread until the completion percentage is 100 OR a timeout is
reached (during which no new progress has been made)."
  (when download-manager:*notifications*
    (loop for d = (calispel:? download-manager:*notifications*)
          while d
          when (download-manager:finished-p d)
            do (hooks:run-hook (after-download-hook *browser*) download-render)
          do (sleep 0.1) ; avoid excessive polling
             (setf (bytes-downloaded download-render)
                   (download-manager:bytes-fetched download-object))
             (setf (completion-percentage download-render)
                   (* 100 (/ (download-manager:bytes-fetched download-object)
                             (max 1 (download-manager:bytes-total download-object))))))))

;; TODO: To download any URL at any moment and not just in resource-query, we
;; need to query the cookies for URL.  Thus we need to add an IPC endpoint to
;; query cookies.
(export-always 'download)
(defmethod download ((buffer buffer) url &key cookies (proxy-url :auto))
  "Download URL.
When PROXY-URL is :AUTO (the default), the proxy address is guessed from the
current buffer.

Return the download object matching the download."
  (hooks:run-hook (before-download-hook *browser*) url) ; TODO: Set URL to download-hook result?
  (prog1
      (match (download-engine buffer)
        (:lisp
         (alex:when-let* ((path (download-directory buffer))
                          (download-dir (files:expand path)))
           (when (eq proxy-url :auto)
             (setf proxy-url (nyxt::proxy-url buffer :downloads-only t)))
           (let* ((download nil))
             (with-protect ("Download error: ~a" :condition)
               (files:with-file-content (downloads path)
                 (setf download
                       (download-manager:resolve url
                                                 :directory download-dir
                                                 :cookies cookies
                                                 :proxy proxy-url))
                 (push download downloads)
                 ;; Add a watcher / renderer for monitoring download
                 (let ((download-render (make-instance 'download :url (render-url url))))
                   (setf (destination-path download-render)
                         (uiop:ensure-pathname
                          (download-manager:filename download)))
                   (push download-render (downloads *browser*))
                   (run-thread
                     "download watcher"
                     (download-watch download-render download)))
                 download)))))
        (:renderer
         (ffi-buffer-download buffer (render-url url))))
    (list-downloads)))

(define-command-global download-url ()
  "Download the page or file of the current buffer."
  (download (current-buffer) (url (current-buffer))))
