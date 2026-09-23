;;; minuet-complete-items-only.el --- Single-item completion prompt -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Prompt customization for Minuet's single-item completion experiment.
;;
;; Load this file after `minuet' to replace the default chat prompt.  The
;; completion API's token limit is not a syntactic boundary, so this feature
;; deliberately relies on the model following the prompt.  FIM providers do
;; not use this prompt; they receive their own prefix/suffix request.

;;; Code:

(require 'minuet)

(defun minuet-complete-items-only--set-prompt (symbol value)
  "Set the customizable completion prompt to VALUE.
SYMBOL is the Custom variable being set.  Keep Minuet's two prompt styles in
sync because providers refer to those variables indirectly through their
option plists."
  (set-default symbol value)
  (setq minuet-default-prompt-prefix-first value
        minuet-default-prompt
        (concat value
                "\nNote that the user input will be provided in **reverse** order: first the\n"
                "context after cursor, followed by the context before cursor.\n")))

(defcustom minuet-completion-prompt
  "You are an AI code completion engine. Provide contextually appropriate completions:
- Code completions in code context
- Comment/documentation text in comments
- String content in string literals
- Prose in markdown/documentation files

Input markers:
- `<contextAfterCursor>`: Context after cursor
- `<cursorPosition>`: Current cursor location
- `<contextBeforeCursor>`: Context before cursor

Complete at most the single syntactic item containing the cursor, such as the
current expression, statement, function, method, struct, class, or scope.
Stop immediately when that item is complete. Never continue with a following
function, declaration, statement, scope, or any other subsequent item. Do not
fill the rest of the file merely because more output tokens are available."
  "Prompt used for single-item chat completions.

This is a prompt-level constraint: completion APIs generally limit tokens but do
not understand language-specific syntactic item boundaries. Models may still
occasionally violate this instruction. Customize this prompt to adapt it to a
specific language or model."
  :type 'string
  :group 'minuet
  :set #'minuet-complete-items-only--set-prompt)

;; Install the feature's default while still allowing a later Custom setting to
;; replace it.  Chat provider option plists use these symbols as prompt values.
(setq minuet-default-prompt-prefix-first minuet-completion-prompt
      minuet-default-prompt
      (concat minuet-completion-prompt
              "\nNote that the user input will be provided in **reverse** order: first the\n"
              "context after cursor, followed by the context before cursor.\n"))

(provide 'minuet-complete-items-only)
;;; minuet-complete-items-only.el ends here
