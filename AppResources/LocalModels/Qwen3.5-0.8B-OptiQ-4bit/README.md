---
library_name: mlx
license: apache-2.0
pipeline_tag: text-generation
base_model: Qwen/Qwen3.5-0.8B
tags:
- mlx
- quantized
- mixed-precision
- 4bit
- 8bit
- optiq
- apple-silicon
- text-generation
- qwen3.5
---

# Qwen3.5-0.8B-OptiQ-4bit

> Optimized for Apple Silicon with [mlx-optiq](https://mlx-optiq.pages.dev/) — sensitivity-aware mixed-precision quantization, reusable at inference, fine-tuning, and serving time.

This is a mixed-precision quantized version of [Qwen/Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B) in MLX format. Instead of uniform 4-bit across every layer, optiq measures each layer's sensitivity via KL divergence on calibration data and assigns **per-layer** bit-widths (some layers at 8-bit, the rest at 4-bit) at the same average bits-per-weight. Same size, higher quality.

The `optiq_metadata.json` sidecar ships in the repo; it's what `mlx-optiq` reads to drive sensitivity-aware LoRA fine-tuning, mixed-precision KV serving, and hot-swap adapter routing.

**Multimodal stripping (default):** the base is published as a multimodal foundation model, but this optiq release ships the language stack only. Vision/audio config + token metadata are dropped at conversion time so the artifact is smaller, leaves more RAM for KV cache + LoRA, and runs cleanly on lower-spec Apple Silicon with longer contexts. If you need the vision tower, re-convert from the base with:

```bash
optiq convert Qwen/Qwen3.5-0.8B --target-bpw 4.5 --keep-unused-modalities -o ./mmodel
```


## Quantization Details

| Property | Value |
|---|---|
| Target BPW | 4.5 |
| Achieved BPW | 4.50 |
| Layers at 8-bit (sensitive) | 76 |
| Layers at 4-bit (robust) | 111 |
| Total quantized layers | 187 |
| Group size | 64 |
| `model_type` | `qwen3_5_text` |

## Usage

### Basic (works with stock `mlx-lm`)

```bash
pip install mlx-lm
```

```python
from mlx_lm import load, generate

model, tokenizer = load("mlx-community/Qwen3.5-0.8B-OptiQ-4bit")
response = generate(
    model, tokenizer,
    prompt="Explain quantum computing in simple terms.",
    max_tokens=200,
)
print(response)
```

### Unlock the full stack with `mlx-optiq`

Installing [mlx-optiq](https://pypi.org/project/mlx-optiq/) turns this model from a static checkpoint into a deployment-ready base:

```bash
pip install mlx-optiq
```

**Mixed-precision KV-cache serving** (+40–62% decode speedup at 64k context on Qwen3.5 2B/4B/9B vs fp16 KV on M3 Max):

```bash
# One-time per-layer KV sensitivity pass
optiq kv-cache mlx-community/Qwen3.5-0.8B-OptiQ-4bit --target-bits 4.5 -o ./kv_cache

# OpenAI-compatible server on :8080
optiq serve \
    --kv-config ./kv_cache/kv_config.json \
    --model mlx-community/Qwen3.5-0.8B-OptiQ-4bit \
    --max-tokens 32768 --temp 0.6 --top-p 0.95
```

**Sensitivity-aware LoRA fine-tuning** — layers optiq kept at 8-bit (more sensitive) get 2× the adapter rank of layers at 4-bit, at the same base budget:

```bash
optiq lora train mlx-community/Qwen3.5-0.8B-OptiQ-4bit \
    --data ./my_data \
    --rank 8 --rank-scaling by_bits \
    --iters 1000 -o ./my_adapter
```

**Hot-swap adapters** — mount N adapters on one base, switch per request without reloading the model (adapter id via HF repo or local path, auto-downloaded):

```bash
optiq serve \
    --model mlx-community/Qwen3.5-0.8B-OptiQ-4bit \
    --adapter ./my_adapter
```

Full documentation: [mlx-optiq.pages.dev](https://mlx-optiq.pages.dev/)

## Benchmarks

See the [Results page](https://mlx-optiq.pages.dev/results.html) for full methodology, per-model GSM8K comparison with uniform 4-bit, and 64k-context KV-serving numbers across the Qwen3.5 lineup.

## Links

- **Documentation:** https://mlx-optiq.pages.dev/
- **PyPI:** https://pypi.org/project/mlx-optiq/
- **Article:** [Not All Layers Are Equal](https://x.com/latent_node/status/2028412948167942334?s=20)
- **Base model:** [Qwen/Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B)

## Credits

- **Quantization method:** [mlx-optiq](https://pypi.org/project/mlx-optiq/)
- **Base model:** [Qwen/Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B)
- **Runtime:** [MLX](https://github.com/ml-explore/mlx)

## License

Apache 2.0 (inherits from base model).
