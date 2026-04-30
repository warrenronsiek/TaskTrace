#!/usr/bin/env python3

import argparse
import math

try:
    from mlx_lm import generate_step, load
except ImportError:
    from mlx_lm import load
    from mlx_lm.utils import generate_step


parser = argparse.ArgumentParser()
parser.add_argument(
    "--model",
    default="models/Qwen3-Reranker-0.6B-4bit",
    help="Local MLX directory or Hugging Face repo id.",
)
args = parser.parse_args()

model, tokenizer = load(args.model)

prefix = (
    "<|im_start|>system\n"
    "Judge whether the Document meets the requirements based on the Query and the Instruct provided. "
    'Note that the answer can only be "yes" or "no".'
    "<|im_end|>\n"
    "<|im_start|>user\n"
)
suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
instruction = "Given a web search query, retrieve relevant passages that answer the query"
query = "What is the capital of China?"

yes_token_id = tokenizer("yes", add_special_tokens=False).input_ids[0]
no_token_id = tokenizer("no", add_special_tokens=False).input_ids[0]

def score(document: str) -> float:
    prompt = (
        f"{prefix}<Instruct>: {instruction}\n"
        f"<Query>: {query}\n"
        f"<Document>: {document}"
        f"{suffix}"
    )
    prompt_tokens = tokenizer.encode(prompt, return_tensors="mlx")[0]
    _, logprobs = next(generate_step(prompt_tokens, model, max_tokens=1))
    yes_probability = math.exp(float(logprobs[yes_token_id].item()))
    no_probability = math.exp(float(logprobs[no_token_id].item()))
    return yes_probability / (yes_probability + no_probability)


relevant_score = score("Beijing is the capital of China.")
irrelevant_score = score("Gravity is a force that attracts two masses.")

print(f"relevant_score={relevant_score:.6f}")
print(f"irrelevant_score={irrelevant_score:.6f}")

if relevant_score <= irrelevant_score:
    raise SystemExit(
        "Reranker smoke test failed: relevant document did not outrank irrelevant document."
    )

print("Reranker smoke test passed.")
