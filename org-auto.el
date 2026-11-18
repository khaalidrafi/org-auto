;;; org-auto.el --- Run per-entry commands at SCHEDULED/DEADLINE time -*- lexical-binding: t; -*-

;; Author: z.ai-agent (GLM-5.3-Flash) <glm-5.3-flash@z.ai>
;; Maintainer: Khalid Rafi <khaalidrafi@gmail.com>
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1") (org "9.1"))
;; Keywords: org, automation, timers

;;; Commentary:

;; Run an Emacs command stored in an Org entry property when that
;; entry's SCHEDULED or DEADLINE time arrives.
;;
;; Example entry:
;;
;;   * TODO Post weekly report
;;     DEADLINE: <2026-11-13 Fri 14:00>
;;     :PROPERTIES:
;;     :EXEC: (my-notify "report due")
;;     :END:
;;
;; The property (`org-auto-property', default "EXEC") holds either an
;; Elisp form starting with "(" or a command name (an optional "M-x "
;; prefix is allowed).  TODO entries only; DONE entries are ignored.
;; An entry may carry both SCHEDULED and DEADLINE - each arms its own
;; timer.  A timestamp without a time-of-day fires at
;; `org-auto-default-time'.
;;
;; While the command runs, `org-auto-current-entry' is bound to
;; (:file FILE :heading HEADING) so the command can act on its entry.
;;
;; Enable globally with (org-auto-mode 1).  Timers are (re)armed when
;; the mode is enabled, after saving an agenda Org file, after
;; `org-auto-idle-delay' seconds of idle time following edits in an
;; agenda Org file, and by hand with M-x org-auto-refresh.
;;
;; At fire time the entry is re-checked against the file on disk: if
;; the heading is gone, DONE, or its EXEC property changed since the
;; timer was armed, the command is skipped.  A stale timer therefore
;; cannot fire a command the user has already cancelled by editing.
;;
;; Limitations: times already in the past are skipped at refresh (no
;; catch-up); repeaters and warning periods are ignored (each
;; timestamp fires once); diary-sexp timestamps are not supported;
;; edits made outside Emacs (git pull, sync tools) are not noticed -
;; run M-x org-auto-refresh after them.

;;; Code:

(require 'org)
(require 'subr-x)

(defgroup org-auto nil
  "Run commands at Org entry SCHEDULED/DEADLINE times."
  :group 'org)

(defcustom org-auto-property "EXEC"
  "Entry property holding the command to run at SCHEDULED/DEADLINE time.
An Elisp form \"(...)\" or a command name."
  :type 'string)

(defcustom org-auto-default-time "09:00"
  "HH:MM used when a timestamp has no time-of-day."
  :type 'string)

(defcustom org-auto-idle-delay 3
  "Seconds of idle time after editing an agenda file before re-arming.
Nil disables re-arming on edits; saving an agenda file always re-arms."
  :type '(choice (natnum) (const nil)))

(defvar org-auto--timers nil
  "All timers armed by `org-auto-refresh'.")

(defvar org-auto--idle-timer nil
  "Pending idle refresh queued by edits, or nil.")

(defvar org-auto-mode nil
  "Non-nil when `org-auto-mode' is on.
Declared early so pre-mode functions can consult it without
a byte-compiler free-variable warning.")

(defvar org-auto-current-entry nil
  "Bound while a command runs: (:file FILE :heading HEADING).")

;;; Scanning

(defun org-auto--collect ()
  "Return (TIME FILE HEADING CMD) items found in `org-agenda-files'.
Only TODO entries carrying `org-auto-property' are collected."
  (let (items)
    (org-map-entries
     (lambda ()
       (let* ((state (org-get-todo-state))
              (cmd (org-entry-get (point) org-auto-property)))
         (when (and cmd (not (string= cmd ""))
                    state (not (member state org-done-keywords)))
           (dolist (ts (delq nil (list (org-entry-get (point) "SCHEDULED")
                                       (org-entry-get (point) "DEADLINE"))))
             (let ((time (org-auto--ts-to-time ts)))
               (when time
                 (push (list time
                             (buffer-file-name)
                             (org-get-heading t t t t)
                             cmd)
                       items)))))))
     nil 'agenda)
    (nreverse items)))

(defun org-auto--ts-to-time (ts)
  "Convert Org timestamp string TS to an absolute time.
Timestamps without a time-of-day get `org-auto-default-time'.
Return nil for diary sexps or strings that cannot be parsed."
  (unless (and (stringp ts) (not (string-prefix-p "<%%" ts)))
    (setq ts nil))
  (when ts
    (condition-case nil
        (let ((base (org-time-string-to-time ts)))
          (if (string-match-p "[0-9]:[0-9]" ts)
              base
            (let* ((dt (decode-time base))
                   (hh (progn (string-match
                               "\\`\\([0-9]+\\):\\([0-9]+\\)"
                               org-auto-default-time)
                              (string-to-number
                               (match-string 1 org-auto-default-time))))
                   (mm (string-to-number
                        (match-string 2 org-auto-default-time))))
              (encode-time (list 0 mm hh
                                 (nth 3 dt) (nth 4 dt) (nth 5 dt)
                                 (nth 6 dt) (nth 7 dt) (nth 8 dt))))))
      (error nil))))

;;; Firing

(defun org-auto--fire (file heading cmd)
  "Run CMD for the entry HEADING in FILE."
  (let ((org-auto-current-entry (list :file file :heading heading))
        (cmd (string-trim (replace-regexp-in-string "\\`M-x +" "" cmd))))
    (condition-case err
        (progn
          (message "org-auto: [%s] %s" heading cmd)
          (if (string-prefix-p "(" cmd)
              (eval (read cmd) t)
            (let ((sym (intern cmd)))
              (if (commandp sym)
                  (command-execute sym)
                (funcall sym)))))
      (error
       (message "org-auto: ERROR [%s]: %s"
                heading (error-message-string err))))))

(defun org-auto--entry-live-p (file heading cmd)
  "Return non-nil if FILE still holds a live TODO entry HEADING with CMD.
Live means: the file is readable, the heading exists, its TODO state
is not DONE, and `org-auto-property' still holds CMD.  Unreadable or
unparsable files count as not live."
  (and (file-readable-p file)
       (condition-case nil
           (catch 'live
             (org-map-entries
              (lambda ()
                (when (and (string= (org-get-heading t t t t) heading)
                           (equal (org-entry-get (point) org-auto-property) cmd)
                           (let ((state (org-get-todo-state)))
                             (and state
                                  (not (member state org-done-keywords)))))
                  (throw 'live t)))
              nil (list file))
             nil)
         (error nil))))

(defun org-auto--fire-maybe (file heading cmd)
  "Fire CMD for HEADING in FILE unless the entry went stale since arming."
  (if (org-auto--entry-live-p file heading cmd)
      (org-auto--fire file heading cmd)
    (message "org-auto: [%s] skipped: entry no longer live (DONE, edited, or gone)"
             heading)))

;;; Arming

(defun org-auto--cancel-all ()
  "Cancel every timer this package armed."
  (mapc #'cancel-timer org-auto--timers)
  (setq org-auto--timers nil))

(defun org-auto-refresh (&optional quiet)
  "Rescan `org-agenda-files' and re-arm all timers.
QUIET non-nil suppresses the summary message (idle-refresh use)."
  (interactive)
  (when org-auto--idle-timer
    (cancel-timer org-auto--idle-timer)
    (setq org-auto--idle-timer nil))
  (org-auto--cancel-all)
  (let* ((now (current-time))
         (all (org-auto--collect))
         future)
    (dolist (item all)
      (when (time-less-p now (nth 0 item))
        (push item future)))
    (setq future (nreverse future))
    (let ((skipped (- (length all) (length future))))
      (dolist (item future)
        (push (run-at-time (nth 0 item) nil #'org-auto--fire-maybe
                           (nth 1 item) (nth 2 item) (nth 3 item))
              org-auto--timers))
      (unless quiet
        (message "org-auto: %d timer(s) armed, %d skipped (past or unparsable)"
                 (length org-auto--timers) skipped)))))

;;; Re-arming triggers

(defun org-auto--after-save ()
  "Refresh after saving an Org agenda file."
  (when (and (buffer-file-name)
             (derived-mode-p 'org-mode)
             (org-agenda-file-p (buffer-file-name)))
    (org-auto-refresh)))

(defun org-auto--after-change (_beg _end _len)
  "Queue a debounced refresh after edits in an agenda file.
The refresh runs after `org-auto-idle-delay' seconds of idle time,
so unsaved edits (moving a SCHEDULED timestamp, marking DONE) are
picked up without waiting for a save."
  (when (and org-auto-idle-delay
             org-auto-mode
             (buffer-file-name)
             (org-agenda-file-p (buffer-file-name)))
    (when org-auto--idle-timer
      (cancel-timer org-auto--idle-timer))
    (setq org-auto--idle-timer
          (run-with-idle-timer org-auto-idle-delay nil
                               #'org-auto-refresh))))

(defun org-auto--turn-on ()
  "Track edits in the current Org buffer (used on `org-mode-hook')."
  (add-hook 'after-change-functions #'org-auto--after-change nil t))

(defun org-auto--turn-on-buffers ()
  "Track edits in every live Org buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'org-mode)
        (org-auto--turn-on)))))

(defun org-auto--turn-off-buffers ()
  "Stop tracking edits in every live Org buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (remove-hook 'after-change-functions #'org-auto--after-change t))))

;;;###autoload
(define-minor-mode org-auto-mode
  "Global mode: run entry EXEC commands at SCHEDULED/DEADLINE time.
Timers re-arm when the mode turns on, when an agenda file is saved,
and after `org-auto-idle-delay' seconds of idle time following edits
in an agenda file."
  :global t
  :group 'org-auto
  (if org-auto-mode
      (progn
        (add-hook 'after-save-hook #'org-auto--after-save)
        (add-hook 'org-mode-hook #'org-auto--turn-on)
        (org-auto--turn-on-buffers)
        (org-auto-refresh))
    (remove-hook 'after-save-hook #'org-auto--after-save)
    (remove-hook 'org-mode-hook #'org-auto--turn-on)
    (org-auto--turn-off-buffers)
    (when org-auto--idle-timer
      (cancel-timer org-auto--idle-timer)
      (setq org-auto--idle-timer nil))
    (org-auto--cancel-all)))

(provide 'org-auto)
;;; org-auto.el ends here
