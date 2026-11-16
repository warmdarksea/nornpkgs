# Regression guard for the transformers pin in lib/models.nix. llama.cpp
# rejects any BPE tokenizer whose digest is missing from its table, and
# transformers 5.x shifts that digest for every LlamaTokenizerFast model --
# a class that includes deepseek-llm, deepseek-coder and their descendants,
# while leaving GPT2/Qwen2 tokenizers alone. So pick a llama-tokenizer
# model, and convert vocab-only: no weights are fetched or read, which puts
# the whole check at a few MB and a couple of seconds.
{ modelLib }:
(modelLib.fetchHuggingFace {
  src = "hf:deepseek-ai/deepseek-coder-1.3b-instruct@e063262dac8366fc1f28a4da0ff3c50ea66259ca";
  files = [ "*.json" ];
  hash = "sha256-Zu8WFs3xBEEpMuccy3A27iCGAxE4XFwOM3lD282DSaA=";
}).gguf.convert { vocabOnly = true; }
