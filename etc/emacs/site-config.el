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

(setq use-package-always-ensure t)
(setq inhibit-startup-message t)
(setq warning-minimum-level :error)
(setq visible-bell 1)

(define-key special-event-map (kbd "<Launch2>") 'ignore)

;; themes
(load "xemacs-theme.el")
(load-theme 'xemacs t t)

(load "vim-default-theme.el")
(load-theme 'vim-default t t)

(load "ansi-theme.el")
(load-theme 'ansi t t)

(load "turbo-theme.el")
(load-theme 'turbo t t)

;; graphical interface setup block
(if (display-graphic-p)
    (progn
      ;; (set-face-attribute 'default nil :family "DejaVu Sans Mono" :height 98)
      (set-face-attribute 'default nil :family "PxPlus IBM VGA 8x16" :height 120)
      (set-face-attribute 'variable-pitch nil :family "PxPlus IBM VGA 8x16" :height 120)
      (set-face-attribute 'bold nil :weight 'normal)
      (message "Loading graphical theme xemacs...")
      (enable-theme 'xemacs))
  (progn
    (message "Loading TTY theme `vim-default'...")
    (enable-theme 'vim-default)))

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

  (define-key key-translation-map (kbd "<f37>") (kbd "S-<return>")))

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

;; key bindings
(define-key key-translation-map (kbd "[") (kbd "("))
(define-key key-translation-map (kbd "]") (kbd ")"))
(define-key key-translation-map (kbd "(") (kbd "{"))
(define-key key-translation-map (kbd ")") (kbd "}"))
(define-key key-translation-map (kbd "{") (kbd "["))
(define-key key-translation-map (kbd "}") (kbd "]"))

(global-set-key (kbd "C-x t") 'insert-tempvar-at-point)

(windmove-default-keybindings 'meta)
(setq windmove-wrap-around t)

;; hotkey for new scratch buffer

(defun new-scratch ()
  "Creates a new scratch buffer"
  (interactive)
  (letrec ((bufname (format "*scratch-%s*" (random-string 5)))
	   (buffer (generate-new-buffer bufname)))
    (set-buffer-major-mode buffer)
    (switch-to-buffer buffer)))
(global-set-key (kbd "C-c s") 'new-scratch)

;; save emacs history
(savehist-mode)

;; ezcompile
(use-package ezcompile
  :config
  (ezcompile-setup-keys))

;; LSP
(use-package lsp-mode
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

(use-package lsp-ui)

(use-package terraform-mode
  :mode   ("\\.tf\\'" . terraform-mode)
  :hook (terraform-mode . (lambda () (lsp)))
  :custom
  (terraform-indent-level 2)
  )

(require 'ansi-color)
(add-hook 'compilation-filter-hook 'ansi-color-compilation-filter)

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

;; magit
(use-package magit
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

(setq-default indent-tabs-mode nil)
(setq-default tab-width 8)
(setq-default standard-indent 2)
(setq-default require-final-newline nil)

(setq-default smie-indent-basic 2)

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
;;	:config
;;	(add-to-list 'auto-mode-alist '("\\.l$" . flex-mode))
;;	(autoload 'flex-mode "flex"))

(use-package bison-mode
  :config
  (add-to-list 'auto-mode-alist '("\\.y$" . bison-mode))
  (autoload 'bison-mode "bison"))

(use-package rust-mode
  :config
  (add-hook 'rust-mode-hook
	    (lambda ()
	      (setq rust-indent-offset 2))))

;; haskell
(add-hook 'haskell-mode-hook #'lsp)
(add-hook 'haskell-literate-mode-hook #'lsp)

;; coq
(use-package proof-general
  ;;	:hook (coq-mode . myfun)
  :after (proof-script proof-useropts)
  :bind (:map proof-mode-map
 	      ("C-<down>" . proof-assert-next-command-interactive))
  :config
  (require 'proof-site "~/.nix-profile/share/emacs/site-lisp/ProofGeneral/generic/proof-site"))

;; scheme
(use-package paredit)
(use-package geiser)
(use-package geiser-chez)

;;
(use-package neotree
  :config
  (global-set-key (kbd "C-d") #'neotree-toggle)
  (setq neo-theme 'arrow))

(use-package ibuffer-sidebar
  :config
  (defvar my-ibuffer-return-window nil)

  (defun my-ibuffer-sidebar-toggle ()
    "Toggle ibuffer sidebar, remembering the source window."
    (interactive)
    (setq my-ibuffer-return-window (selected-window))
    (ibuffer-sidebar-toggle-sidebar))

  (advice-add 'ibuffer-visit-buffer :around
              (lambda (orig &rest args)
                (let ((buf (ibuffer-current-buffer t)))
                  (ibuffer-sidebar-hide-sidebar)
                  (when (and my-ibuffer-return-window
                             (window-live-p my-ibuffer-return-window))
                    (select-window my-ibuffer-return-window))
                  (switch-to-buffer buf))))

  (global-set-key (kbd "C-S-d") #'my-ibuffer-sidebar-toggle))

(use-package all-the-icons)

;;
(use-package forth-mode)

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
(use-package lean4-mode)
(use-package flycheck)

(use-package nix-mode
  :config
  ;; SMIE broken can't change indent offset width
  ;; (setq nix-indent-function 'nix-indent-line)
  (add-to-list 'auto-mode-alist '("\\.nix\\'" . nix-mode)))

(use-package nix-buffer)
(use-package gnuplot-mode)
(use-package yaml-mode)

;;
(setq compilation-scroll-output t)
(setq compilation-always-kill t)
