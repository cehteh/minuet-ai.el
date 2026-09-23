# PoC: cached whole-file summaries

This branch implements a proof of concept for [upstream discussion #63](https://github.com/milanglacier/minuet-ai.el/discussions/63).

## Design

`minuet-context-summary.el` introduces a **secondary chat-model configuration**. It is intentionally independent of `minuet-provider`, so a FIM completion model can remain the primary model while a separate chat/reasoning model summarizes the buffer.

The summary is:

- opt-in via `minuet-context-summary-mode`;
- cached buffer-locally and guarded by `buffer-chars-modified-tick`;
- refreshed explicitly with `M-x minuet-context-summary-refresh`, on visiting a file, or after saving;
- never requested from `after-change-functions`;
- treated as a prompt hint, with `minuet-context-summary-target-length` passed to the model rather than enforced locally;
- included only in chat completion prompts, not FIM requests;
- discarded when the buffer changes until the next explicit/load/save refresh.

The PoC backend is OpenAI-compatible, which covers Ollama, llama.cpp chat endpoints, OpenRouter, and similar services.

## Example

```elisp
(require 'minuet-context-summary)

(setq minuet-context-summary-provider 'openai-compatible)
(setq minuet-context-summary-target-length 2000)
(setq minuet-context-summary-openai-compatible-options
      '(:model "qwen2.5-coder:7b"
        :end-point "http://localhost:11434/v1/chat/completions"
        :api-key "TERM"
        :system "Summarize source code for completion."))

(add-hook 'prog-mode-hook #'minuet-context-summary-mode)
```

For a cloud backend, change `:end-point`, `:model`, and `:api-key`. The API-key value follows Minuet's convention: it is normally the name of an environment variable.

## Follow-up work

- Share the existing provider transport and response extraction instead of maintaining a PoC-specific OpenAI-compatible request.
- Add native Claude and Gemini summary backends.
- Add project/include discovery with explicit privacy controls.
- Add latency and acceptance-rate benchmarks against baseline context windows.
- Decide whether summary refresh should be debounced after save or remain explicitly user-controlled.
