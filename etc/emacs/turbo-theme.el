;; turbo-theme.el --- A theme inspired by Turbo C++ IDE

(deftheme turbo
  "A theme inspired by the classic Turbo C++ IDE.")

(let ((class '((class color) (min-colors 89)))
      ;; Color palette
      (turbo-bg "#000080")        ; Dark blue background
      (turbo-fg "#ffffff")        ; White text
      (turbo-cyan "#00ffff")      ; Cyan for highlights
      (turbo-gray "#808080")      ; Gray for comments
      (turbo-yellow "#ffff00")    ; Yellow for keywords
      (turbo-green "#00ff00")     ; Green for strings
      (turbo-red "#ff0000")       ; Red for warnings
      (turbo-border "#00ffff"))   ; Cyan border

  (custom-theme-set-faces
   'turbo
   
   ;; Basic faces
   `(default ((,class (:foreground ,turbo-fg :background ,turbo-bg))))
   `(cursor ((,class (:background ,turbo-cyan))))
   `(region ((,class (:background ,turbo-cyan :foreground ,turbo-bg))))
   `(highlight ((,class (:background ,turbo-cyan :foreground ,turbo-bg))))
   `(fringe ((,class (:background ,turbo-bg))))
   `(border ((,class (:foreground ,turbo-border))))
   
   ;; Mode line
   `(mode-line ((,class (:foreground ,turbo-bg :background ,turbo-cyan :box (:line-width -1 :color ,turbo-cyan)))))
   `(mode-line-inactive ((,class (:foreground ,turbo-cyan :background ,turbo-bg :box (:line-width -1 :color ,turbo-border)))))
   
   ;; Font lock
   `(font-lock-builtin-face ((,class (:foreground ,turbo-cyan))))
   `(font-lock-comment-face ((,class (:foreground ,turbo-gray))))
   `(font-lock-constant-face ((,class (:foreground ,turbo-yellow))))
   `(font-lock-doc-face ((,class (:foreground ,turbo-gray))))
   `(font-lock-function-name-face ((,class (:foreground ,turbo-cyan))))
   `(font-lock-keyword-face ((,class (:foreground ,turbo-yellow))))
   `(font-lock-string-face ((,class (:foreground ,turbo-green))))
   `(font-lock-type-face ((,class (:foreground ,turbo-cyan))))
   `(font-lock-variable-name-face ((,class (:foreground ,turbo-fg))))
   `(font-lock-warning-face ((,class (:foreground ,turbo-red :bold t))))

   ;; Show paren
   `(show-paren-match ((,class (:background ,turbo-cyan :foreground ,turbo-bg))))
   `(show-paren-mismatch ((,class (:background ,turbo-red :foreground ,turbo-fg))))
   
   ;; Line highlight
   `(hl-line ((,class (:background "#000098"))))
   
   ;; Mini buffer
   `(minibuffer-prompt ((,class (:foreground ,turbo-cyan :bold t))))
   
   ;; Window borders
   `(vertical-border ((,class (:foreground ,turbo-border))))))

;;;###autoload
(when load-file-name
  (add-to-list 'custom-theme-load-path
               (file-name-as-directory (file-name-directory load-file-name))))

(provide-theme 'turbo)
;;; turbo-theme.el ends here