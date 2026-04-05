;;; ezcompile.el --- Project-local build command management -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Manage per-project build/test/clean commands via .dir-locals.el.
;;
;; Each project has:
;;   - A directory to run commands in
;;   - Named slots (build, test, clean) each with a list of commands to cycle
;;
;; Usage in .dir-locals.el:
;;
;;   ((nil . ((ezcompile-directory . "/home/user/proj/foo")
;;            (ezcompile-slots . (("build" "make -j16" "make -C submod -j16")
;;                                ("test"  "make test")
;;                                ("clean" "make clean"))))))
;;
;; Keybindings (set up by ezcompile-setup-keys):
;;   C-b         run current build command
;;   C-v         run current test command
;;   C-f         run current clean command
;;   C-z b / B   cycle build commands forward / backward
;;   C-z v / V   cycle test commands forward / backward
;;   C-z f / F   cycle clean commands forward / backward

;;; Code:

;; --- Project-local variables (set via .dir-locals.el) ---

(defvar-local ezcompile-directory nil
  "Directory to run commands in.  If nil, uses `default-directory'.")

(defvar-local ezcompile-slots '()
  "Alist of (SLOT-NAME COMMAND ...) for this project.
Each entry is a list: the car is the slot name (a string),
the cdr is a list of shell command strings to cycle through.")

;; Mark as safe for dir-locals
(put 'ezcompile-directory 'safe-local-variable #'string-or-null-p)
(put 'ezcompile-slots 'safe-local-variable #'listp)

;; --- Internal state ---

(defvar ezcompile--indices (make-hash-table :test 'equal)
  "Hash table mapping (DIRECTORY . SLOT-NAME) to current command index.
Persists across buffer switches but not across sessions.")

(defun ezcompile--index-key (slot)
  "Return a hash key for SLOT in the current project."
  (cons (or ezcompile-directory default-directory) slot))

(defun ezcompile--get-index (slot)
  "Get the current command index for SLOT."
  (gethash (ezcompile--index-key slot) ezcompile--indices 0))

(defun ezcompile--set-index (slot idx)
  "Set the current command index for SLOT to IDX."
  (puthash (ezcompile--index-key slot) idx ezcompile--indices))

(defun ezcompile--get-commands (slot)
  "Get the list of commands for SLOT."
  (cdr (assoc slot ezcompile-slots #'string=)))

(defun ezcompile--current-command (slot)
  "Get the current command string for SLOT."
  (let* ((commands (ezcompile--get-commands slot))
         (idx (ezcompile--get-index slot)))
    (when commands
      (nth (mod idx (length commands)) commands))))

(defun ezcompile--inherit-from-dir-locals ()
  "Walk up from `default-directory' and load ezcompile vars from .dir-locals.el."
  (when-let ((root (locate-dominating-file default-directory ".dir-locals.el")))
    (let* ((file (expand-file-name ".dir-locals.el" root))
           (alist (with-temp-buffer
                    (insert-file-contents file)
                    (goto-char (point-min))
                    (condition-case nil (read (current-buffer)) (error nil))))
           (nil-alist (cdr (assoc nil alist))))
      (when-let ((slots (alist-get 'ezcompile-slots nil-alist)))
        (setq-local ezcompile-slots slots))
      (when-let ((dir (alist-get 'ezcompile-directory nil-alist)))
        (setq-local ezcompile-directory dir)))))

;; --- Core commands ---

(defun ezcompile-run (slot)
  "Run the current command for SLOT in `compilation-mode'."
  (when (null ezcompile-slots)
    (ezcompile--inherit-from-dir-locals))
  (let ((cmd (ezcompile--current-command slot)))
    (if (null cmd)
        (user-error "No commands for slot `%s'.  Set `ezcompile-slots' in .dir-locals.el" slot)
      (let ((default-directory (or ezcompile-directory default-directory)))
        (compile cmd t)))))

(defun ezcompile-cycle (slot n)
  "Cycle by N steps in SLOT and display the new current command.
Positive N cycles forward, negative N cycles backward."
  (let ((commands (ezcompile--get-commands slot)))
    (if (null commands)
        (user-error "No commands for slot `%s'" slot)
      (let* ((idx (ezcompile--get-index slot))
             (new-idx (mod (+ idx n) (length commands))))
        (ezcompile--set-index slot new-idx)
        (message "[%s %d/%d] %s"
                 slot (1+ new-idx) (length commands)
                 (nth new-idx commands))))))

;; --- Interactive editing ---

(defun ezcompile--read-slot (&optional prompt)
  "Read a slot name, offering existing slots as completion."
  (completing-read (or prompt "Slot: ")
                   (mapcar #'car ezcompile-slots)
                   nil nil nil nil "build"))

(defun ezcompile-add (slot command)
  "Add COMMAND to SLOT.  Creates the slot if it doesn't exist.
Sets `ezcompile-directory' to the nearest .dir-locals.el location
if not already set."
  (interactive
   (list (ezcompile--read-slot "Add to slot: ")
         (read-string "Command: ")))
  (unless ezcompile-directory
    (setq ezcompile-directory
          (or (when-let ((dl (locate-dominating-file default-directory ".dir-locals.el")))
                (expand-file-name dl))
              default-directory))
    (message "ezcompile directory set to %s" ezcompile-directory))
  (let ((entry (assoc slot ezcompile-slots #'string=)))
    (if entry
        (setcdr entry (append (cdr entry) (list command)))
      (setq ezcompile-slots (append ezcompile-slots (list (list slot command))))))
  (message "Added to [%s]: %s" slot command))

(defun ezcompile-remove (slot command)
  "Remove COMMAND from SLOT."
  (interactive
   (let* ((slot (ezcompile--read-slot "Remove from slot: "))
          (commands (ezcompile--get-commands slot))
          (command (completing-read "Remove command: " commands nil t)))
     (list slot command)))
  (let ((entry (assoc slot ezcompile-slots #'string=)))
    (when entry
      (setcdr entry (delete command (cdr entry)))
      ;; Clean up empty slots
      (when (null (cdr entry))
        (setq ezcompile-slots
              (cl-remove slot ezcompile-slots :key #'car :test #'string=)))))
  (message "Removed from [%s]: %s" slot command))

(defun ezcompile-show ()
  "Display the current ezcompile configuration."
  (interactive)
  (let ((dir (or ezcompile-directory default-directory)))
    (message "ezcompile: dir=%s\n%s"
             dir
             (mapconcat
              (lambda (entry)
                (let* ((slot (car entry))
                       (commands (cdr entry))
                       (idx (ezcompile--get-index slot)))
                  (format "  [%s %d/%d] %s"
                          slot (1+ idx) (length commands)
                          (string-join commands " | "))))
              ezcompile-slots "\n"))))

;; --- Persistence (save to .dir-locals.el) ---

(defun ezcompile-save ()
  "Save current ezcompile configuration to .dir-locals.el.
Writes `ezcompile-slots' and `ezcompile-directory'."
  (interactive)
  (let* ((dir (or ezcompile-directory default-directory))
         (dlfile (expand-file-name ".dir-locals.el" dir))
         (existing (when (file-exists-p dlfile)
                     (with-temp-buffer
                       (insert-file-contents dlfile)
                       (goto-char (point-min))
                       (condition-case nil
                           (read (current-buffer))
                         (error nil)))))
         ;; Get or create the nil-mode alist
         (nil-entry (or (assoc nil existing) '(nil)))
         (nil-alist (cdr nil-entry)))
    ;; Update the nil-mode alist
    (setq nil-alist (assq-delete-all 'ezcompile-slots nil-alist))
    (setq nil-alist (assq-delete-all 'ezcompile-directory nil-alist))
    (when ezcompile-slots
      (push (cons 'ezcompile-slots ezcompile-slots) nil-alist))
    (when ezcompile-directory
      (push (cons 'ezcompile-directory ezcompile-directory) nil-alist))
    ;; Rebuild the full alist
    (setq existing (cl-remove nil existing :key #'car))
    (push (cons nil nil-alist) existing)
    ;; Write it out
    (with-temp-file dlfile
      (insert ";;; Directory Local Variables -*- no-byte-compile: t; -*-\n")
      (insert ";;; For more information see (info \"(emacs) Directory Variables\")\n\n")
      (pp existing (current-buffer)))
    (message "Saved ezcompile config to %s" dlfile)))

;; --- Named slot commands ---

(defun ezcompile-build () "Run current build command." (interactive) (ezcompile-run "build"))
(defun ezcompile-test ()  "Run current test command."  (interactive) (ezcompile-run "test"))
(defun ezcompile-clean () "Run current clean command." (interactive) (ezcompile-run "clean"))

(defun ezcompile-cycle-build-forward ()  "Cycle build forward."  (interactive) (ezcompile-cycle "build"  1))
(defun ezcompile-cycle-build-backward () "Cycle build backward." (interactive) (ezcompile-cycle "build" -1))
(defun ezcompile-cycle-test-forward ()   "Cycle test forward."   (interactive) (ezcompile-cycle "test"   1))
(defun ezcompile-cycle-test-backward ()  "Cycle test backward."  (interactive) (ezcompile-cycle "test"  -1))
(defun ezcompile-cycle-clean-forward ()  "Cycle clean forward."  (interactive) (ezcompile-cycle "clean"  1))
(defun ezcompile-cycle-clean-backward () "Cycle clean backward." (interactive) (ezcompile-cycle "clean" -1))

;; --- Key bindings ---

(defun ezcompile-setup-keys ()
  "Set up default ezcompile keybindings.
C-b/C-v/C-f for build/test/clean.
C-z b/v/f for cycling forward, C-z B/V/F for cycling backward."
  (global-set-key (kbd "C-b") #'ezcompile-build)
  (global-set-key (kbd "C-v") #'ezcompile-test)
  (global-set-key (kbd "C-f") #'ezcompile-clean)
  (define-prefix-command 'ezcompile-cycle-map)
  (global-set-key (kbd "C-z") #'ezcompile-cycle-map)
  (define-key ezcompile-cycle-map (kbd "b") #'ezcompile-cycle-build-forward)
  (define-key ezcompile-cycle-map (kbd "B") #'ezcompile-cycle-build-backward)
  (define-key ezcompile-cycle-map (kbd "v") #'ezcompile-cycle-test-forward)
  (define-key ezcompile-cycle-map (kbd "V") #'ezcompile-cycle-test-backward)
  (define-key ezcompile-cycle-map (kbd "f") #'ezcompile-cycle-clean-forward)
  (define-key ezcompile-cycle-map (kbd "F") #'ezcompile-cycle-clean-backward))

(provide 'ezcompile)
;;; ezcompile.el ends here
