(eval-when-compile
  ;; Following line is not needed if use-package.el is in ~/.emacs.d
  (require 'use-package))

;; Never auto-download: fail if a :ensure’d package isn't already present
;; written by chatgpt o4-mini
(setq use-package-ensure-function
      (lambda (name _keyword ensure-p)
        (when ensure-p
          (unless (package-installed-p name)
            (error "Package %S not found; please install/manage it via Nix" name)))))

(setq inhibit-startup-message t)
(setq comp-deferred-compilation nil)
(setq native-comp-speed -1)
(setq native-comp-deferred-compilation-deny-list '(".*"))
(setq-default no-native-compile t)
(setq warning-minimum-level :error)
(setq visible-bell 1)
(setq use-package-always-ensure t)

(define-key special-event-map (kbd "<Launch2>") 'ignore)

;; graphical interface setup block
(if (display-graphic-p)
    (progn
      (message "Loading graphical theme xemacs...")
      (load-file "xemacs-theme.el")
      (load-theme 'xemacs t))
  (progn
    (message "Loading TTY theme `vim-default'...")
    (load-file "vim-default-theme.el")
    (load-theme 'vim-default t)))

;; TTY setup block
(unless (display-graphic-p)
  ;; console setup script for linux framebuffer console
  ;; requires supporting vconsole keymap configuration
  ;; thx https://www.emacswiki.org/emacs/LinuxConsoleKeys#h5o-1

  ;; TTY Key hacks
  ;; The translations with the settings below fit the adjustments to the key table.
  (define-key input-decode-map "\e[25~" [(f13)])
  (define-key input-decode-map "\e[26~" [(f14)])
  (define-key input-decode-map "\e[28~" [(f15)])
  (define-key input-decode-map "\e[29~" [(f16)])
  (define-key input-decode-map "\e[31~" [(f17)])
  (define-key input-decode-map "\e[32~" [(f18)])
  (define-key input-decode-map "\e[33~" [(f19)])
  (define-key input-decode-map "\e[34~" [(f20)])
  (define-key input-decode-map "\e[35~" [(f21)])
  (define-key input-decode-map "\e[36~" [(f22)])
  (define-key input-decode-map "\e[37~" [(f23)])
  (define-key input-decode-map "\e[38~" [(f24)])
  (define-key input-decode-map "\e[39~" [(f25)])
  (define-key input-decode-map "\e[40~" [(f26)])
  (define-key input-decode-map "\e[41~" [(f27)])
  (define-key input-decode-map "\e[42~" [(f28)])
  (define-key input-decode-map "\e[43~" [(f29)])
  (define-key input-decode-map "\e[44~" [(f30)])
  (define-key input-decode-map "\e[45~" [(f31)])
  (define-key input-decode-map "\e[46~" [(f32)])
  (define-key input-decode-map "\e[47~" [(f33)])
  (define-key input-decode-map "\e[48~" [(f34)])
  (define-key input-decode-map "\e[49~" [(f35)])
  (define-key input-decode-map "\e[50~" [(f36)])
  (define-key input-decode-map "\e[51~" [(f37)])
  (define-key input-decode-map "\e[52~" [(f38)])
  (define-key input-decode-map "\e[53~" [(f39)])
  (define-key input-decode-map "\e[54~" [(f40)])

  (define-key key-translation-map (kbd "<f13>") (kbd "<C-return>"))
  (define-key key-translation-map (kbd "<f14>") (kbd "<C-S-return>"))
  ;;(define-key key-translation-map (kbd "<f15loadkeys /path/to/xtrakeys.txt >") (kbd "<M-S-return>"))

  (define-key key-translation-map (kbd "<f16>") (kbd "M-S-<left>"))
  (define-key key-translation-map (kbd "<f17>") (kbd "M-S-<right>"))
  (define-key key-translation-map (kbd "<f18>") (kbd "M-S-<up>"))
  (define-key key-translation-map (kbd "<f19>") (kbd "M-S-<down>"))

  (define-key key-translation-map (kbd "<f20>") (kbd "M-<left>"))
  (define-key key-translation-map (kbd "<f21>") (kbd "M-<right>"))
  (define-key key-translation-map (kbd "<f22>") (kbd "M-<up>"))
  (define-key key-translation-map (kbd "<f23>") (kbd "M-<down>"))

  (define-key key-translation-map (kbd "<f24>") (kbd "C-<left>"))
  (define-key key-translation-map (kbd "<f25>") (kbd "C-<right>"))
  (define-key key-translation-map (kbd "<f26>") (kbd "C-<up>"))
  (define-key key-translation-map (kbd "<f27>") (kbd "C-<down>"))

  (define-key key-translation-map (kbd "<f28>") (kbd "S-<left>"))
  (define-key key-translation-map (kbd "<f29>") (kbd "S-<right>"))
  (define-key key-translation-map (kbd "<f30>") (kbd "S-<up>"))
  (define-key key-translation-map (kbd "<f31>") (kbd "S-<down>"))

  (define-key key-translation-map (kbd "<f32>") (kbd "C-S-<left>"))
  (define-key key-translation-map (kbd "<f33>") (kbd "C-S-<right>"))
  (define-key key-translation-map (kbd "<f34>") (kbd "C-S-<up>"))
  (define-key key-translation-map (kbd "<f35>") (kbd "C-S-<down>"))

  (define-key key-translation-map (kbd "<f36>") (kbd "S-<tab>"))

  (define-key key-translation-map (kbd "<f37>") (kbd "S-<return>"))

  ;; key locker
  (defun lock-screen ()
    (interactive)
    (progn
      ;;			(insecure-lock-mode)))
      (shell-command "physlock")))
  (global-set-key (kbd "C-c l") 'lock-screen))
;;	(add-hook 'after-change-major-mode-hook (lambda () (global-set-key (kbd "C-c C-l") 'lock-screen))))
;;(setq native-comp-speed -1)
;;(setq comp-deferred-compilation nil)
;;(setq package-native-compile t)

;; include paths

;; packaging
(require 'package)
(package-initialize)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

;; lib

(defun increment-char-at-point ()
  "Increment number or character at point."
  (interactive)
  (condition-case nil
      (save-excursion
        (let ((chr  (1+ (char-after))))
          (unless (characterp chr) (error "Cannot increment char by one"))
          (delete-char 1)
          (insert chr)))
    (error (error "No character at point"))))

;; tempvars

;; ty https://emacs.stackexchange.com/a/7150
(defun tempvars-in-buffer ()
  (save-match-data
    (let ((pos 0)
          matches)
      (while (string-match "t[0-9]+" (buffer-string) pos)
        (push (match-string 0 (buffer-string)) matches)
        (setq pos (match-end 0)))
      matches)))

(defun tempvars-next (temps)
  (let ((nums (mapcar (lambda (x)
			(string-to-number (substring x 1))) temps)))
    (if (null nums)
	"t0"
      (concat "t" (number-to-string (+ 1 (seq-max nums)))))))

(defun insert-tempvar-at-point ()
  (interactive)
  (insert (tempvars-next (tempvars-in-buffer))))

;; key bindings
(define-key key-translation-map (kbd "[") (kbd "("))
(define-key key-translation-map (kbd "]") (kbd ")"))
(define-key key-translation-map (kbd "(") (kbd "{"))
(define-key key-translation-map (kbd ")") (kbd "}"))
(define-key key-translation-map (kbd "{") (kbd "["))
(define-key key-translation-map (kbd "}") (kbd "]"))

(global-set-key (kbd "C-x t") 'insert-tempvar-at-point)

;; hotkey for new scratch buffer
;; thanks https://stackoverflow.com/questions/37038441
(defun random-alnum ()
  (let* ((alnum "abcdefghijklmnopqrstuvwxyz0123456789")
	 (i (% (abs (random)) (length alnum))))
    (substring alnum i (1+ i))))
(defun random-string (n)
  "Generate a slug of n random alphanumeric characters.
   Inefficient implementation; don't use for large n."
  (if (= 0 n)
      ""
    (concat (random-alnum) (random-string (1- n)))))

(defun new-scratch ()
  "Creates a new scratch buffer"
  (interactive)
  (letrec ((bufname (format "*scratch-%s*" (random-string 5)))
	   (buffer (generate-new-buffer bufname)))
    (set-buffer-major-mode buffer)
    (switch-to-buffer buffer)))
(global-set-key (kbd "C-c s") 'new-scratch)

;; splash
;;(require 'splash)
;;(setq splash-mode-image "~/.emacs.d/marivector.png")
;;(new-splash-buffer)

;; desktop+
;;(require 'desktop+)


;; save emacs history
(savehist-mode)

;; projectile
;; (use-package projectile
;; 	:ensure t
;; 	:init
;; 	(setq projectile-project-search-path '("~/proj" "~/tmp/projectile-test" "~/proj/tassel"))
;; 	:config
;; 	(projectile-mode +1)
;; 	(define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
;; 	(define-key projectile-mode-map (kbd "C-v") 'projectile-test-project)

;; 	(defun my-projectile-run-project (&optional prompt)
;; 		(interactive "P")
;; 		(let ((compilation-read-command
;; 					 (or (not (projectile-run-command (projectile-compilation-dir)))
;; 							 prompt)))
;; 			(projectile-run-project prompt))))

;; (global-set-key (kbd "C-b") 'projectile-compile-project)
;; (global-set-key (kbd "C-v") 'projectile-test-project)
;; (global-set-key (kbd "C-f") 'projectile-run-project)

;; ty https://emacs.stackexchange.com/a/13096
(defun my-reload-dir-locals-for-current-buffer ()
  "reload dir locals for the current buffer"
  (interactive)
  (let ((enable-local-variables :all))
    (hack-dir-local-variables-non-file-buffer)))

(defun my-reload-dir-locals-for-all-buffer-in-this-directory ()
  "For every buffer with the same `default-directory` as the 
current buffer's, reload dir-locals."
  (interactive)
  (let ((dir default-directory))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (equal default-directory dir)
          (my-reload-dir-locals-for-current-buffer))))))

(add-hook 'emacs-lisp-mode-hook
          (defun enable-autoreload-for-dir-locals ()
            (when (and (buffer-file-name)
                       (equal dir-locals-file
                              (file-name-nondirectory (buffer-file-name))))
              (add-hook 'after-save-hook
                        'my-reload-dir-locals-for-all-buffer-in-this-directory
                        nil t))))

(defvar ezcompile-build-commands '()
  "List of build commands to cycle through")

(defvar ezcompile-test-commands '()
  "List of test commands to cycle through")

(defvar ezcompile-clean-commands '())

(defvar ezcompile-current-build 0)
(defvar ezcompile-current-test 0)
(defvar ezcompile-current-clean 0)

(defun ezcompile-cycle-build ()
  (interactive)
  (setq ezcompile-current-build 
        (mod (1+ ezcompile-current-build) (length ezcompile-build-commands)))
  (message "Build command: %s" (nth ezcompile-current-build ezcompile-build-commands)))

(defun ezcompile-cycle-test ()
  (interactive)
  (setq ezcompile-current-test
        (mod (1+ ezcompile-current-test) (length ezcompile-test-commands)))
  (message "Test command: %s" (nth ezcompile-current-test ezcompile-test-commands)))

(defun ezcompile-cycle-clean ()
  (interactive)
  (setq ezcompile-current-clean
        (mod (1+ ezcompile-current-clean) (length ezcompile-clean-commands)))
  (message "Clean command: %s" (nth ezcompile-current-clean ezcompile-clean-commands)))

(defun ezcompile-build ()
  (interactive)
  (compile (nth ezcompile-current-build ezcompile-build-commands) t))

(defun ezcompile-test ()
  (interactive)
  (add-hook 'comint-mode-hook #'compilation-minor-mode t)
  (compile (nth ezcompile-current-test ezcompile-test-commands) t)
  (remove-hook 'comint-mode-hook #'compilation-minor-mode))

(defun ezcompile-clean ()
  (interactive)
  (compile (nth ezcompile-current-clean ezcompile-clean-commands) t))

;; (defun ezcompile-build ()
;;   (interactive)
;;   (compile ezcompile-build-command t))
;; (defun ezcompile-test ()
;;   (interactive)
;;   (add-hook 'comint-mode-hook #'compilation-minor-mode t)
;;   (compile ezcompile-test-command t)
;;   (remove-hook 'comint-mode-hook #'compilation-minor-mode))
;; (defun ezcompile-clean ()
;;   (interactive)
;;   (compile ezcompile-clean-command t))

;; (defvar ezcompile-build-commands '()
;;   "List of build commands to cycle through")

;; (defvar ezcompile-test-commands '()
;;   "List of test commands to cycle through")

;; (defvar ezcompile-current-build 0)
;; (defvar ezcompile-current-test 0)

;(global-set-key (kbd "C-b") 'ezcompile-build)
;(global-set-key (kbd "C-v") 'ezcompile-test)
;(global-set-key (kbd "C-f") 'ezcompile-clean)

(global-set-key (kbd "C-b") 'ezcompile-build)
(global-set-key (kbd "C-v") 'ezcompile-test)
(global-set-key (kbd "C-f") 'ezcompile-clean)

;; get rid of the annoying suspend-frame
(global-unset-key (kbd "C-z"))
;; optionally also unset C-x C-z which does the same thing
(global-unset-key (kbd "C-x C-z"))

(define-prefix-command 'ezcompile-cycle-map)
(global-set-key (kbd "C-z") 'ezcompile-cycle-map)
(define-key ezcompile-cycle-map (kbd "b") 'ezcompile-cycle-build)
(define-key ezcompile-cycle-map (kbd "v") 'ezcompile-cycle-test)
(define-key ezcompile-cycle-map (kbd "f") 'ezcompile-cycle-clean)

;; LSP
(use-package lsp-mode
  :ensure t
  :init
  ;; set prefix for lsp-command-keymap (few alternatives - "C-l", "C-c l")
  (setq lsp-disabled-clients '(tfls))
  (setq lsp-terraform-server "terraform-ls")
  (setq lsp-keymap-prefix "C-c l")
  ;;(setq lsp-haskell-ghc-options '("-w"))
  (setq lsp-diagnostics-provider :none)
  :hook (;; replace XXX-mode with concrete major-mode(e. g. python-mode)
         ;;(XXX-mode . lsp)
         ;; if you want which-key integration
         ;;(lsp-mode . lsp-enable-which-key-integration))
	 terraform-mode
	 )
  :commands lsp)

(use-package lsp-ui
  :ensure t)

(use-package terraform-mode
  :ensure t
  :mode   ("\\.tf\\'" . terraform-mode)
  :hook (terraform-mode . (lambda () (lsp)))
  :custom
  (terraform-indent-level 2)
  )

;;
;; (use-package redacted :ensure t)
;; (use-package posframe :ensure t)
;; (use-package insecure-lock
;; 	:ensure t
;; 	:config
;; 	(insecure-lock-run-idle 300) ;; Lock screen after 300 seconds
;; 	(setq 'insecure-lock-mode-hook '(insecure-lock-blank-screen insecure-lock-posframe)) ;; Enable date time display
;; 	)

;; optionally
;;(use-package lsp-ui :commands lsp-ui-mode)
;; if you are helm user
;;(use-package helm-lsp :commands helm-lsp-workspace-symbol)
;; if you are ivy user
;;(use-package lsp-ivy :commands lsp-ivy-workspace-symbol)
;;(use-package lsp-treemacs :commands lsp-treemacs-errors-list)

;; optionally if you want to use debugger
;;(use-package dap-mode)
;; (use-package dap-LANGUAGE) to load the dap adapter for your language

;; optional if you want which-key integration
;;(use-package which-key
;;    :config
;;    (which-key-mode))

;; (global-ede-mode t)

;; org-mode
(setq org-tags-column 0)
(setq org-todo-keywords '((sequence "TODO(t)" "|" "CANCEL(c)" "UNABLE(u)" "FAIL(f)" "PARTIAL(p)" "DONE(d)")))
(setq org-capture-templates '(("n" "note" entry (file "~/txt/note.org")
                               "* <%<%Y-%m-%d %a %H:%M:%S %Z>>\n  %?")
                              ("j" "journal" entry (file "~/txt/journal.org")
                               "* <%<%Y-%m-%d %a %H:%M:%S %Z>>\n  %?")
                              ("w" "words" entry (file "~/txt/words.org")
                               "* <%<%Y-%m-%d %a %H:%M:%S %Z>> %?\n** Definition\n** Example")))
(global-set-key (kbd "C-c c") 'org-capture)
(setq org-support-shift-select t)
(setq org-image-actual-width 450)
(setq org-startup-with-inline-images 'inlineimages)
(org-babel-do-load-languages
 'org-babel-load-languages
 '((shell . t)
   (gnuplot . t)
   (scheme . t)))

;; wayland binary clipboard stuff
;; when you paste binary data into emacs, it copies it to a file and pastes
;; the path to you
(if (string-equal (window-system) "pgtk")
    (progn
      (setq wl-paste-location "~/Pictures/Screenshots")
      (setq wl-paste-template "emacs.XXXXXXXXXX.png")

      (setq wl-copy-process nil)
      (defun wl-copy (text)
	(setq wl-copy-process (make-process :name "wl-copy"
					    :buffer nil
					    :command '("wl-copy" "-f" "-n")
					    :connection-type 'pipe))
	(process-send-string wl-copy-process text)
	(process-send-eof wl-copy-process))
      (defun wl-paste ()
	(if (and wl-copy-process (process-live-p wl-copy-process))
	    nil ; should return nil if we're the current paste owner
	  (letrec ((types (shell-command-to-string "wl-paste -l"))
		   (tokens (split-string types "\n")))
	    (if (eq '() (member "text/plain" tokens)) ; if clipboard does not contain text
		(progn
		  (if (not (boundp 'wl-paste-dict))
		      (setq wl-paste-dict (make-hash-table :test 'equal)))
		  (letrec ((paste (shell-command-to-string "wl-paste"))
			   (path (gethash paste wl-paste-dict)))
		    (if (not (eq path '()))
			path
		      (let ((path (shell-command-to-string (format "mktemp -p %s %s" wl-paste-location wl-paste-template))))
			(progn
			  (puthash paste path wl-paste-dict)
			  (shell-command (format "wl-paste > %s" path))
			  path)))))
	      (shell-command-to-string "wl-paste -n | tr -d \r")))))
      (setq interprogram-cut-function 'wl-copy)
      (setq interprogram-paste-function 'wl-paste)))

;; magit
;;(require 'magit)
;;(setq magit-commit-arguments '("--allow-empty-message"))
;;(transient-append-suffix 'magit-commit "c"
;;   '("--allow-empty-message" "Allow empty commit message" magit-allow-empty-message))
(use-package magit
  :ensure t
  :config
  (defun magit-empty-commit (&optional args)
    "Creates a new empty commit"
    (interactive (if current-prefix-arg
                     (list (cons "--amend" (magit-commit-arguments)))
                   (list (magit-commit-arguments))))
    (when (member "--all" args)
      (setq this-command 'magit-commit-all))
    (when (setq args (magit-commit-assert args))
      (let ((default-directory (magit-toplevel)))
        (magit-run-git "commit" "--allow-empty-message" "-m" "" args))))
  (transient-append-suffix 'magit-commit "c"
    '("E" "Empty commit" magit-empty-commit)))

;; look and feel
(tool-bar-mode -1)
(menu-bar-mode -99)

(setq multi-term-program "/run/current-system/sw/bin/bash")

(column-number-mode)
(when (version<= "26.0.50" emacs-version)
  (global-display-line-numbers-mode))
(global-hl-line-mode +1)

;; disable various forms of electric indentation
;; (setq-default indent-tabs-mode nil)
;; (setq-default electric-indent-mode -1)
;; (setq indent-line-function 'insert-tab)

(setq-default indent-tabs-mode nil)
(setq-default tab-width 8)
(setq-default standard-indent 2)
(setq-default require-final-newline nil)
;;(setq-default indent-line-function 'insert-tab)

(setq-default smie-indent-basic 2)

(add-hook 'after-change-major-mode-hook 
          (lambda ()
            (progn
;	      (setq indent-tabs-mode nil)
;              (setq tab-width 8)
;              (setq standard-indent 2)
;              (electric-indent-mode -1)
;              (setq require-final-newline nil)
)))
;; 2 space tabstop
;(setq default-tab-width 2)
;(setq-default tab-width 2)
;(setq tab-stop-list '(2 4 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60 62 64 66 68 70 72 74 76 78 80 82 84 86 88 90 92 94 96 98 100 102 104 106 108 110 112 114 116 118 120))
;(setq python-indent-offset 2)
;(setq js-indent-level 2)

;; c
(setq c-basic-offset 2)
(defun my-c-mode-common-hook ()
  (electric-indent-mode 1)
  (setq c-default-style "k&r")
  (setq indent-tabs-mode nil)
  (setq c-basic-offset 2)
  (c-set-offset 'case-label 2)
  (c-set-offset 'statement-case-intro 0)
  (c-set-offset 'arglist-cont-nonempty
                (lambda (langelem)
                  ;; (message "%s" c-syntactic-context)
                  (cond
                   ((assoc 'brace-list-intro c-syntactic-context)
                    '0)
                   ((assoc 'brace-list-close c-syntactic-context)
                    '0)
                   (t 'c-lineup-arglist-intro-after-paren)))))
(add-hook 'c-mode-common-hook 'my-c-mode-common-hook)

;;(use-package flex-mode
;;	:ensure t
;;	:config
;;	(add-to-list 'auto-mode-alist '("\\.l$" . flex-mode))
;;	(autoload 'flex-mode "flex"))

(use-package bison-mode
  :ensure t
  :config
  (add-to-list 'auto-mode-alist '("\\.y$" . bison-mode))
  (autoload 'bison-mode "bison"))

(use-package rust-mode
  :ensure t
  :config
  (add-hook 'rust-mode-hook
	    (lambda ()
	      (setq rust-indent-offset 2))))

;; haskell
;; (use-package haskell-mode
;;   :ensure t
;;   ;;	:ensure haskell-interactive-mode
;; 					;	:ensure haskell-process
;;   :config
;; 					;(require 'haskell-interactive-mode)
;; 					;(require 'haskell-process)
;;   (add-hook 'haskell-mode-hook 'interactive-haskell-mode)
;;   (define-key haskell-mode-map (kbd "C-c C-l") 'haskell-process-load-or-reload)
;;   (define-key haskell-mode-map (kbd "C-`") 'haskell-interactive-bring)
;;   (define-key haskell-mode-map (kbd "C-c C-t") 'haskell-process-do-type)
;;   (define-key haskell-mode-map (kbd "C-c C-i") 'haskell-process-do-info)
;;   (define-key haskell-mode-map (kbd "C-c C-c") 'haskell-process-cabal-build)
;;   (define-key haskell-mode-map (kbd "C-c C-k") 'haskell-interactive-mode-clear)
;;   (define-key haskell-mode-map (kbd "C-c c") 'haskell-process-cabal))

(add-hook 'haskell-mode-hook #'lsp)
(add-hook 'haskell-literate-mode-hook #'lsp)

;(setq lsp-haskell-plugin-hlint-enabled nil)           ;; Turn off HLint suggestions
;(setq lsp-haskell-plugin-stan-enabled nil)            ;; Turn off Stan (performance warnings)
;;(setq lsp-haskell-plugin-stylish-haskell-enabled nil) ;; Turn off style formatter
;;(setq lsp-haskell-plugin-fourmolu-enabled nil)        ;; Turn off fourmolu formatter
;;(setq lsp-haskell-plugin-ormolu-enabled nil)          ;; Turn off ormolu formatter
;;(setq lsp-haskell-plugin-ghcide-type-lenses-enabled nil) ;; Turn off inline type hints
  
;; (setq lsp-haskell-ghc-options '("-Wno-name-shadowing"))

;; (setq lsp-diagnostic-provider :none) ;; Turn off all diagnostics

;(with-eval-after-load 'lsp-mode
;  ;; Only show critical errors
;  (setq lsp-diagnostics-filter 
;        (lambda (diagnostic)
;          ;; Only keep diagnostics with "Error" severity (1)
;          (eq (lsp:diagnostic-severity? diagnostic) 1))))

;; coq
(use-package proof-general
  :ensure t
  ;;	:hook (coq-mode . myfun)
  :after (proof-script proof-useropts)
  :bind (:map proof-mode-map
 	      ("C-<down>" . proof-assert-next-command-interactive))
  :config
  (require 'proof-site "~/.nix-profile/share/emacs/site-lisp/ProofGeneral/generic/proof-site"))

;; scheme
(use-package paredit
  :ensure t)

(use-package geiser
  :ensure t)

(use-package geiser-chez
  :ensure t)

(use-package neotree
  :ensure t
  :config
  (global-set-key [f8] 'neotree-toggle)
  (setq neo-theme (if (display-graphic-p) 'icons 'arrow)))

(use-package all-the-icons
  :ensure t)

(use-package forth-mode
  :ensure t)

;; make forth actually use theme colors

(font-lock-add-keywords
 'forth-mode
 '(("\\<\\(DUP\\|DROP\\|SWAP\\|ROT\\|OVER\\)\\>" . font-lock-function-name-face)  ; stack ops = pink now
   ("\\<\\(IF\\|ELSE\\|THEN\\|BEGIN\\|WHILE\\|REPEAT\\|UNTIL\\)\\>" . font-lock-keyword-face)  ; yellow
   ("\\<\\(CR\\|EMIT\\|\\.\\|TYPE\\)\\>" . font-lock-constant-face)   ; still pink
   ("\\<[0-9]+\\>" . font-lock-constant-face)))

;; make comments work right
(setq forth-mode-comment-regexp "\\\\.*$")

;; lean
(require 'lean4-mode)
(require 'flycheck)

;; hotkey for new scratch buffer
;; thanks https://stackoverflow.com/questions/37038441
(defun random-alnum ()
  (let* ((alnum "abcdefghijklmnopqrstuvwxyz0123456789")
	 (i (% (abs (random)) (length alnum))))
    (substring alnum i (1+ i))))
(defun random-string (n)
  "Generate a slug of n random alphanumeric characters.
   Inefficient implementation; don't use for large n."
  (if (= 0 n)
      ""
    (concat (random-alnum) (random-string (1- n)))))

(defun new-scratch ()
  "Creates a new scratch buffer"
  (interactive)
  (letrec ((bufname (format "*scratch-%s*" (random-string 5)))
	   (buffer (generate-new-buffer bufname)))
    (set-buffer-major-mode buffer)
    (switch-to-buffer buffer)))
(global-set-key (kbd "C-c s") 'new-scratch)

;; splash
;;(require 'splash)
;;(setq splash-mode-image "~/.emacs.d/marivector.png")
;;(new-splash-buffer)

;; desktop+
;;(require 'desktop+)


;; save emacs history
(savehist-mode)

;; projectile
;; (use-package projectile
;; 	:ensure t
;; 	:init
;; 	(setq projectile-project-search-path '("~/proj" "~/tmp/projectile-test" "~/proj/tassel"))
;; 	:config
;; 	(projectile-mode +1)
;; 	(define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
;; 	(define-key projectile-mode-map (kbd "C-v") 'projectile-test-project)

;; 	(defun my-projectile-run-project (&optional prompt)
;; 		(interactive "P")
;; 		(let ((compilation-read-command
;; 					 (or (not (projectile-run-command (projectile-compilation-dir)))
;; 							 prompt)))
;; 			(projectile-run-project prompt))))

;; (global-set-key (kbd "C-b") 'projectile-compile-project)
;; (global-set-key (kbd "C-v") 'projectile-test-project)
;; (global-set-key (kbd "C-f") 'projectile-run-project)

;; (global-ede-mode t)

;; org-mode
(setq org-tags-column 0)
(setq org-todo-keywords '((sequence "TODO(t)" "|" "CANCEL(c)" "UNABLE(u)" "FAIL(f)" "PARTIAL(p)" "DONE(d)")))
(setq org-capture-templates '(("n" "note" entry (file "~/txt/note.org")
                               "* <%<%Y-%m-%d %a %H:%M:%S %Z>>\n  %?")
                              ("j" "journal" entry (file "~/txt/journal.org")
                               "* <%<%Y-%m-%d %a %H:%M:%S %Z>>\n  %?")
                              ("w" "words" entry (file "~/txt/words.org")
                               "* <%<%Y-%m-%d %a %H:%M:%S %Z>> %?\n** Definition\n** Example")))
(global-set-key (kbd "C-c c") 'org-capture)
(setq org-support-shift-select t)
(setq org-image-actual-width 450)
(setq org-startup-with-inline-images 'inlineimages)

(use-package nix-mode
  :ensure t
  :config
  ;; SMIE broken can't change indent offset width
  ;; (setq nix-indent-function 'nix-indent-line)
  (add-to-list 'auto-mode-alist '("\\.nix\\'" . nix-mode)))

(use-package nix-buffer
  :ensure t)

;;
(use-package gnuplot-mode
  :ensure t)

(use-package yaml-mode
  :ensure t)

;;
;;(add-hook 'prog-mode-hook 'rainbow-delimiters-mode)

;;
(setq compilation-scroll-output t)
(setq compilation-always-kill t)

;;
;;(autoload 'sawfish-mode "sawfish" "sawfish-mode" t)
;;(setq auto-mode-alist (cons '("\\.sawfishrc$"  . sawfish-mode) auto-mode-alist)
;;      auto-mode-alist (cons '("\\.jl$"         . sawfish-mode) auto-mode-alist)
;;      auto-mode-alist (cons '("\\.sawfish/rc$" . sawfish-mode) auto-mode-alist))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(browse-url-browser-function 'eww-browse-url)
 '(column-number-mode t)
 '(compilation-message-face 'default)
 '(connection-local-criteria-alist
   '(((:application tramp :protocol "flatpak")
      tramp-container-connection-local-default-flatpak-profile)
     ((:application tramp)
      tramp-connection-local-default-system-profile tramp-connection-local-default-shell-profile)))
 '(connection-local-profile-alist
   '((tramp-container-connection-local-default-flatpak-profile
      (tramp-remote-path "/app/bin" tramp-default-remote-path "/bin" "/usr/bin" "/sbin" "/usr/sbin" "/usr/local/bin" "/usr/local/sbin" "/local/bin" "/local/freeware/bin" "/local/gnu/bin" "/usr/freeware/bin" "/usr/pkg/bin" "/usr/contrib/bin" "/opt/bin" "/opt/sbin" "/opt/local/bin"))
     (tramp-connection-local-darwin-ps-profile
      (tramp-process-attributes-ps-args "-acxww" "-o" "pid,uid,user,gid,comm=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" "-o" "state=abcde" "-o" "ppid,pgid,sess,tty,tpgid,minflt,majflt,time,pri,nice,vsz,rss,etime,pcpu,pmem,args")
      (tramp-process-attributes-ps-format
       (pid . number)
       (euid . number)
       (user . string)
       (egid . number)
       (comm . 52)
       (state . 5)
       (ppid . number)
       (pgrp . number)
       (sess . number)
       (ttname . string)
       (tpgid . number)
       (minflt . number)
       (majflt . number)
       (time . tramp-ps-time)
       (pri . number)
       (nice . number)
       (vsize . number)
       (rss . number)
       (etime . tramp-ps-time)
       (pcpu . number)
       (pmem . number)
       (args)))
     (tramp-connection-local-busybox-ps-profile
      (tramp-process-attributes-ps-args "-o" "pid,user,group,comm=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" "-o" "stat=abcde" "-o" "ppid,pgid,tty,time,nice,etime,args")
      (tramp-process-attributes-ps-format
       (pid . number)
       (user . string)
       (group . string)
       (comm . 52)
       (state . 5)
       (ppid . number)
       (pgrp . number)
       (ttname . string)
       (time . tramp-ps-time)
       (nice . number)
       (etime . tramp-ps-time)
       (args)))
     (tramp-connection-local-bsd-ps-profile
      (tramp-process-attributes-ps-args "-acxww" "-o" "pid,euid,user,egid,egroup,comm=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" "-o" "state,ppid,pgid,sid,tty,tpgid,minflt,majflt,time,pri,nice,vsz,rss,etimes,pcpu,pmem,args")
      (tramp-process-attributes-ps-format
       (pid . number)
       (euid . number)
       (user . string)
       (egid . number)
       (group . string)
       (comm . 52)
       (state . string)
       (ppid . number)
       (pgrp . number)
       (sess . number)
       (ttname . string)
       (tpgid . number)
       (minflt . number)
       (majflt . number)
       (time . tramp-ps-time)
       (pri . number)
       (nice . number)
       (vsize . number)
       (rss . number)
       (etime . number)
       (pcpu . number)
       (pmem . number)
       (args)))
     (tramp-connection-local-default-shell-profile
      (shell-file-name . "/bin/sh")
      (shell-command-switch . "-c"))
     (tramp-connection-local-default-system-profile
      (path-separator . ":")
      (null-device . "/dev/null"))))
 '(coq-prog-args '("-coqlib" "/home/marisa/local/coq/lib/coq" "-emacs-U"))
 '(cua-global-mark-cursor-color "#2aa198")
 '(cua-normal-cursor-color "#839496")
 '(cua-overwrite-cursor-color "#b58900")
 '(cua-read-only-cursor-color "#859900")
 '(custom-safe-themes
   '("0615f6940c6c5e5638c9157644263889db755d43576c25f7b311806f4cfe2c3a" "2809bcb77ad21312897b541134981282dc455ccd7c14d74cc333b6e549b824f3" "0fffa9669425ff140ff2ae8568c7719705ef33b7a927a0ba7c5e2ffcfac09b75" "274fa62b00d732d093fc3f120aca1b31a6bb484492f31081c1814a858e25c72e" "834cbeacb6837f3ddca4a1a7b19b1af3834f36a701e8b15b628cad3d85c970ff" "3860a842e0bf585df9e5785e06d600a86e8b605e5cc0b74320dfe667bcbe816c" "6b3ec7b218feca3b56e00554cd47c3a465ad423e4366f27af5e3ed895129e734" "c9b89349d269af4ac5d832759df2f142ae50b0bbbabcce9c0dd53f79008443c9" "bffa9739ce0752a37d9b1eee78fc00ba159748f50dc328af4be661484848e476" "50b64810ed1c36dfb72d74a61ae08e5869edc554102f20e078b21f84209c08d1" "0c3b1358ea01895e56d1c0193f72559449462e5952bded28c81a8e09b53f103f" "760ce657e710a77bcf6df51d97e51aae2ee7db1fba21bbad07aab0fa0f42f834" "9be1d34d961a40d94ef94d0d08a364c3d27201f3c98c9d38e36f10588469ea57" "e1498b2416922aa561076edc5c9b0ad7b34d8ff849f335c13364c8f4276904f0" "a95e86f310e90576a64ef75e5be5d8d8dfc051435af3be59c5f8b5b1b60d82c2" "cc60d17db31a53adf93ec6fad5a9cfff6e177664994a52346f81f62840fe8e23" default))
 '(ede-project-directories
   '("/home/satori/tmp/edeproject/include" "/home/satori/tmp/edeproject/src" "/home/satori/tmp/edeproject" "/home/satori/proj/tassel/src"))
 '(fci-rule-color "#5E5E5E")
 '(frame-resize-pixelwise t)
 '(fringe-mode 6 nil (fringe))
 '(geiser-debug-jump-to-debug nil)
 '(geiser-default-implementation 'chez)
 '(highlight-changes-colors '("#d33682" "#6c71c4"))
 '(highlight-symbol-colors
   '("#3b6b40f432d6" "#07b9463c4d36" "#47a3341e358a" "#1d873c3f56d5" "#2d86441c3361" "#43b7362d3199" "#061d417f59d7"))
 '(highlight-symbol-foreground-color "#93a1a1")
 '(highlight-tail-colors
   '(("#073642" . 0)
     ("#5b7300" . 20)
     ("#007d76" . 30)
     ("#0061a8" . 50)
     ("#866300" . 60)
     ("#992700" . 70)
     ("#a00559" . 85)
     ("#073642" . 100)))
 '(hl-bg-colors
   '("#866300" "#992700" "#a7020a" "#a00559" "#243e9b" "#0061a8" "#007d76" "#5b7300"))
 '(hl-fg-colors
   '("#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36" "#002b36"))
 '(hl-paren-colors '("#2aa198" "#b58900" "#268bd2" "#6c71c4" "#859900"))
 '(hl-todo-keyword-faces
   '(("TODO" . "#dc752f")
     ("NEXT" . "#dc752f")
     ("THEM" . "#2d9574")
     ("PROG" . "#4f97d7")
     ("OKAY" . "#4f97d7")
     ("DONT" . "#f2241f")
     ("FAIL" . "#f2241f")
     ("DONE" . "#86dc2f")
     ("NOTE" . "#b1951d")
     ("KLUDGE" . "#b1951d")
     ("HACK" . "#b1951d")
     ("TEMP" . "#b1951d")
     ("FIXME" . "#dc752f")
     ("XXX+" . "#dc752f")
     ("\\?\\?\\?+" . "#dc752f")))
 '(linum-format 'dynamic)
 '(lsp-ui-doc-border "#93a1a1")
 '(lsp-haskell-plugin-stan-global-on nil)
 ;;'(lsp-haskell-diagnostics-enabled nil)
 ;;'(lsp-haskell-plugin-hlint-diagnostics-on nil)
 ;;'(lsp-haskell-ghc-options '("-w"))
 ;;'(lsp-diagnostics-provider :none)
 '(menu-bar-mode nil)
 '(native-comp-jit-compilation-deny-list '(".*"))
 '(nrepl-message-colors
   '("#dc322f" "#cb4b16" "#b58900" "#5b7300" "#b3c34d" "#0061a8" "#2aa198" "#d33682" "#6c71c4"))
 '(org-agenda-files
   '("~/tmp/note/00000000-0000-0000-0000-000000000000" "~/tmp/note/00000000-0000-0000-0000-000000000000" "~/tmp/note/00000000-0000-0000-0000-000000000000"))
 '(org-startup-truncated nil)
 '(package-selected-packages
   '(cmake-mode terraform-mode lua-mode nix-buffer yaml-mode bison-mode exec-path-from-shell proof-general solarized-theme magit org-journal benchmark-init dashboard gnu-elpa-keyring-update dracula-theme hc-zenburn-theme grandshell-theme overcast-theme bubbleberry-theme spacemacs-theme base16-theme tuareg lavender-theme sr-speedbar ggtags iedit anzu comment-dwim-2 ws-butler dtrt-indent clean-aindent-mode yasnippet undo-tree volatile-highlights helm-gtags helm-projectile helm-swoop helm zygospore projectile company use-package glsl-mode vala-mode websocket web-server uuidgen sml-mode rust-mode rainbow-identifiers rainbow-delimiters rainbow-blocks racket-mode protobuf-mode paredit nasm-mode multi-term markdown-mode jedi-direx haskell-mode go-mode cherry-blossom-theme))
 '(pdf-view-midnight-colors '("#b2b2b2" . "#292b2e"))
 '(pos-tip-background-color "#073642")
 '(pos-tip-foreground-color "#93a1a1")
 '(powerline-color1 "#3d3d68")
 '(powerline-color2 "#292945")
 '(require-final-newline nil)
 '(safe-local-variable-values
   '((eval progn
	   (setq savehist-file "/nonexistant/.emacs_history")
	   (savehist-mode 1))
     (compilation-default-directory . "/home/satori/proj/tassel/TASSEL0")
     (eval progn
	   (setq savehist-file "/home/satori/proj/tassel/.emacs_history")
	   (savehist-mode 1))
     (compilation-read-command)
     (ezcompile-test-command . "make -C /home/satori/proj/tassel/TASSEL0 -j16 run_qemu_img TARGET=amd64")
     (ezcompile-test-command . "make -C /home/satori/proj/tassel/TASSEL0 -j16 run_qemu_img_tty TARGET=amd64")
     (ezcompile-clean-command . "make -C /home/satori/proj/tassel/TASSEL0 -j16 clean")
     (projectile-project-test-cmd . "make a.out && make run")
     (projectile-project-run-cmd . "make run")
     (projectile-project-compilation-cmd . "make a.out")
     (projectile-project-compilation-dir . "./src")))
 '(smartrep-mode-line-active-bg (solarized-color-blend "#859900" "#073642" 0.2))
 '(tool-bar-mode nil)
 '(truncate-lines nil)
 '(vc-annotate-background "#202020")
 '(vc-annotate-background-mode nil)
 '(vc-annotate-color-map
   '((20 . "#C99090")
     (40 . "#D9A0A0")
     (60 . "#ECBC9C")
     (80 . "#DDCC9C")
     (100 . "#EDDCAC")
     (120 . "#FDECBC")
     (140 . "#6C8C6C")
     (160 . "#8CAC8C")
     (180 . "#9CBF9C")
     (200 . "#ACD2AC")
     (220 . "#BCE5BC")
     (240 . "#CCF8CC")
     (260 . "#A0EDF0")
     (280 . "#79ADB0")
     (300 . "#89C5C8")
     (320 . "#99DDE0")
     (340 . "#9CC7FB")
     (360 . "#E090C7")))
 '(vc-annotate-very-old-color "#E090C7")
 '(weechat-color-list
   '(unspecified "#002b36" "#073642" "#a7020a" "#dc322f" "#5b7300" "#859900" "#866300" "#b58900" "#0061a8" "#268bd2" "#a00559" "#d33682" "#007d76" "#2aa198" "#839496" "#657b83"))
 '(xterm-color-names
   ["#073642" "#dc322f" "#859900" "#b58900" "#268bd2" "#d33682" "#2aa198" "#eee8d5"])
 '(xterm-color-names-bright
   ["#002b36" "#cb4b16" "#586e75" "#657b83" "#839496" "#6c71c4" "#93a1a1" "#fdf6e3"]))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "DejaVu Sans Mono" :foundry "unknown" :slant normal :weight normal :height 98 :width normal))))
 '(term-color-blue ((t nil)))
 '(term-color-cyan ((t (:background "cyan3" :foreground "cyan4"))))
 '(term-color-green ((t (:background "green3" :foreground "green4"))))
 '(term-color-magenta ((t (:background "magenta3" :foreground "magenta4"))))
 '(term-color-red ((t (:background "red3" :foreground "red4"))))
 '(term-color-yellow ((t (:background "yellow3" :foreground "yellow4"))))
 '(whitespace-space ((t nil)))
 '(whitespace-tab ((t (:background "#1F102F" :foreground "#F94FA0"))))
 '(whitespace-trailing ((t (:background "#1f102f")))))
(put 'downcase-region 'disabled nil)
(put 'upcase-region 'disabled nil)
