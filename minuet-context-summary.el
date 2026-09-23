;;; minuet-context-summary.el --- Cached whole-buffer context summaries -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Experimental proof of concept for discussion #63.  A secondary chat model
;; summarizes the current buffer.  The result is cached and included in chat
;; completion prompts; it is refreshed explicitly, on visiting a file, or after
;; saving, never on every change.

;;; Code:

(require 'json)
(require 'plz)
(require 'minuet)

(defgroup minuet-context-summary nil
  "Cached whole-buffer summaries for Minuet completions."
  :group 'minuet)

(defcustom minuet-context-summary-enabled nil
  "Whether to include a cached summary in chat completion prompts."
  :type 'boolean)

(defcustom minuet-context-summary-provider 'openai-compatible
  "Backend used to generate summaries.
The PoC currently supports `openai-compatible'."
  :type '(choice (const openai-compatible)))

(defcustom minuet-context-summary-target-length 2000
  "Suggested summary length in characters.
This is a prompt hint, not a hard limit."
  :type 'integer)

(defcustom minuet-context-summary-request-timeout 30
  "Maximum time in seconds for a summary request."
  :type 'number)

(defcustom minuet-context-summary-openai-compatible-options
  '(:model "qwen2.5-coder:7b"
    :end-point "http://localhost:11434/v1/chat/completions"
    :api-key "TERM"
    :system "You summarize source files for a code completion assistant."
    :optional nil)
  "Secondary chat-model configuration used for summaries.
`:api-key' names an environment variable, just like Minuet provider options."
  :type 'plist)

(defcustom minuet-context-summary-prompt
  "Summarize this source file for another code-completion model.

Include the file's purpose, important symbols, data flow, invariants,
interfaces, dependencies visible in the file, and conventions to preserve.
Be factual and concise. Aim for approximately %d characters, but prioritize
useful information over the exact length. Do not use markdown fences."
  "Prompt sent to the summary model."
  :type 'string)

(defvar-local minuet-context-summary--text nil)
(defvar-local minuet-context-summary--tick nil)
(defvar-local minuet-context-summary--request nil)

(defun minuet-context-summary--api-key (value)
  "Resolve API key environment variable VALUE."
  (cond ((functionp value) (funcall value))
        ((and (stringp value) (getenv value)) (getenv value))
        ((stringp value) value)
        (t nil)))

(defun minuet-context-summary--valid-p ()
  "Return non-nil when the cached summary belongs to this buffer state."
  (and (stringp minuet-context-summary--text)
       minuet-context-summary--tick
       (= minuet-context-summary--tick (buffer-chars-modified-tick))))

(defun minuet-context-summary--prompt ()
  "Build the summary request prompt from the current buffer."
  (format "%s\n\n<source>\n%s\n</source>"
          (format minuet-context-summary-prompt
                  minuet-context-summary-target-length)
          (buffer-substring-no-properties (point-min) (point-max))))

(defun minuet-context-summary--extract (json)
  "Extract assistant text from OpenAI-compatible response JSON."
  (when-let* ((choices (plist-get json :choices))
              (choice (car choices))
              (message (plist-get choice :message)))
    (plist-get message :content)))

(defun minuet-context-summary--finish (buffer tick response)
  "Install RESPONSE in BUFFER if it still has modification TICK."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq minuet-context-summary--request nil)
      (when (and response (= tick (buffer-chars-modified-tick)))
        (setq minuet-context-summary--text response
              minuet-context-summary--tick tick)))))

(defun minuet-context-summary--request-openai-compatible ()
  "Request a summary using the configured OpenAI-compatible chat backend."
  (let* ((options minuet-context-summary-openai-compatible-options)
         (api-key (minuet-context-summary--api-key
                   (plist-get options :api-key)))
         (endpoint (plist-get options :end-point))
         (tick (buffer-chars-modified-tick))
         (buffer (current-buffer))
         (body `(:model ,(plist-get options :model)
                 :stream :json-false
                 :messages [(:role "system" :content
                                      ,(plist-get options :system))
                            (:role "user" :content ,(minuet-context-summary--prompt))]
                 ,@(plist-get options :optional)))
         (headers `(("Content-Type" . "application/json")
                    ("Accept" . "application/json")
                    ("Authorization" . ,(concat "Bearer " api-key)))))
    (setq minuet-context-summary--request
          (plz 'post endpoint
            :headers headers
            :timeout minuet-context-summary-request-timeout
            :body (json-serialize body)
            :as 'string
            :then (lambda (response)
                    (let ((text (minuet-context-summary--extract
                                 (json-parse-string response
                                   :object-type 'plist :array-type 'list))))
                      (minuet-context-summary--finish buffer tick text)))
            :else (lambda (err)
                    (setq minuet-context-summary--request nil)
                    (minuet--log (format "Minuet context summary error: %s" err)))))))

;;;###autoload
(defun minuet-context-summary-refresh ()
  "Refresh the cached summary for the current buffer."
  (interactive)
  (when (and minuet-context-summary-enabled
             (not (process-live-p minuet-context-summary--request)))
    (setq minuet-context-summary--text nil
          minuet-context-summary--tick nil)
    (pcase minuet-context-summary-provider
      ('openai-compatible (minuet-context-summary--request-openai-compatible)))))

(defun minuet-context-summary--refresh-after-save ()
  "Refresh the summary after saving the current buffer."
  (minuet-context-summary-refresh))

(defun minuet-context-summary--refresh-on-load ()
  "Refresh the summary when a file buffer is visited."
  (when (and minuet-context-summary-enabled buffer-file-name)
    (minuet-context-summary-refresh)))

(defun minuet-context-summary--augment-chat-shot (original context options)
  "Add the cached summary to the chat shot returned by ORIGINAL."
  (let ((shots (funcall original context options)))
    (if (and minuet-context-summary-enabled
             (minuet-context-summary--valid-p)
             (consp shots))
        (cons (format "<fileSummary>\n%s\n</fileSummary>\n\n%s"
                      minuet-context-summary--text (car shots))
              (cdr shots))
      shots)))

(define-minor-mode minuet-context-summary-mode
  "Use a cached secondary-model summary in Minuet chat prompts."
  :group 'minuet-context-summary
  :lighter " Sum"
  (if minuet-context-summary-mode
      (progn
        (setq minuet-context-summary-enabled t)
        (add-hook 'after-save-hook #'minuet-context-summary--refresh-after-save nil t)
        (advice-add 'minuet--make-chat-llm-shot :around
                    #'minuet-context-summary--augment-chat-shot)
        (minuet-context-summary-refresh))
    (remove-hook 'after-save-hook #'minuet-context-summary--refresh-after-save t)
    (advice-remove 'minuet--make-chat-llm-shot
                   #'minuet-context-summary--augment-chat-shot)
    (when (process-live-p minuet-context-summary--request)
      (delete-process minuet-context-summary--request))
    (setq minuet-context-summary--request nil
          minuet-context-summary--text nil
          minuet-context-summary--tick nil)))

(add-hook 'find-file-hook #'minuet-context-summary--refresh-on-load)

(provide 'minuet-context-summary)
;;; minuet-context-summary.el ends here
