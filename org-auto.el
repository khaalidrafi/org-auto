;;; org-auto.el --- Run per-entry commands at SCHEDULED/DEADLINE time -*- lexical-binding: t; -*-

;; Author: z.ai-agent (GLM-5.3-Flash) <glm-5.3-flash@z.ai>
;; Maintainer: Khalid Rafi <khaalidrafi@gmail.com>
;; Version: 0.1.0
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
;; the mode is enabled, after saving an agenda Org file, and by hand
;; with M-x org-auto-refresh.
;;
;; Limitations: times already in the past are skipped at refresh (no
;; catch-up); repeaters and warning periods are ignored (each
;; timestamp fires once); diary-sexp timestamps are not supported.

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

(defvar org-auto--timers nil
  "All timers armed by `org-auto-refresh'.")

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

;;; Arming

(defun org-auto--cancel-all ()
  "Cancel every timer this package armed."
  (mapc #'cancel-timer org-auto--timers)
  (setq org-auto--timers nil))

(defun org-auto-refresh ()
  "Rescan `org-agenda-files' and re-arm all timers."
  (interactive)
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
        (push (run-at-time (nth 0 item) nil #'org-auto--fire
                           (nth 1 item) (nth 2 item) (nth 3 item))
              org-auto--timers))
      (message "org-auto: %d timer(s) armed, %d skipped (past or unparsable)"
               (length org-auto--timers) skipped))))

(defun org-auto--after-save ()
  "Refresh after saving an Org agenda file."
  (when (and (buffer-file-name)
             (derived-mode-p 'org-mode)
             (member (expand-file-name (buffer-file-name))
                     (mapcar #'expand-file-name (org-agenda-files))))
    (org-auto-refresh)))

;;;###autoload
(define-minor-mode org-auto-mode
  "Global mode: run entry EXEC commands at SCHEDULED/DEADLINE time."
  :global t
  :group 'org-auto
  (if org-auto-mode
      (progn
        (add-hook 'after-save-hook #'org-auto--after-save)
        (org-auto-refresh))
    (remove-hook 'after-save-hook #'org-auto--after-save)
    (org-auto--cancel-all)))

(provide 'org-auto)
;;; org-auto.el ends here
