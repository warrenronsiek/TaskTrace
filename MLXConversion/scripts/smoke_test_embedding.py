#!/usr/bin/env python3

import argparse

import mlx.core as mx
from mlx_embeddings import generate, load


parser = argparse.ArgumentParser()
parser.add_argument(
    "--model",
    default="models/Qwen3-Embedding-0.6B-4bit",
    help="Local MLX directory or Hugging Face repo id.",
)
args = parser.parse_args()

model, processor = load(args.model)

texts = [
    "search_query: What is the capital of China?",
    "search_document: Beijing is the capital of China.",
    "search_document: Gravity is a force that attracts two masses.",
]

output = generate(model, processor, texts=texts)
similarity = mx.matmul(output.text_embeds, output.text_embeds.T)

relevant_score = float(similarity[0, 1].item())
irrelevant_score = float(similarity[0, 2].item())

print(f"relevant_score={relevant_score:.6f}")
print(f"irrelevant_score={irrelevant_score:.6f}")

if relevant_score <= irrelevant_score:
    raise SystemExit(
        "Embedding smoke test failed: relevant document did not outrank irrelevant document."
    )

print("Embedding smoke test passed.")
