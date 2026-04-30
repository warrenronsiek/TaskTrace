# MLXConversion

`MLXConversion` is the standalone workspace for producing the local model artifacts that ship inside TaskTrace.

There are two different workflows here:

- convert upstream retrieval models into MLX artifacts
- vendor already-MLX model repos directly into `AppResources/LocalModels`

The retrieval conversion models are:

- `Qwen/Qwen3-Embedding-0.6B`
- `Qwen/Qwen3-Reranker-0.6B`

The bundled MLX-native app models are:

- `mlx-community/Qwen3.5-4B-OptiQ-4bit`
- `mlx-community/Qwen3.5-0.8B-OptiQ-4bit`
- `mlx-community/gemma-4-e2b-it-4bit`

## Current conclusion

We do not need a fresh Swift-side architecture port for any of these models.

- The current `mlx-swift-lm` checkout already has a `qwen3` implementation inside `MLXEmbedders`.
- The same checkout already registers `qwen3` as a supported embedder `model_type`.
- Hugging Face already has MLX community conversions for both target models.
- MLX community model cards for these Qwen3 retrieval repos indicate the artifacts are produced via `mlx_embeddings`.
- The app text and visual models are already published as MLX-native repos, so they should be vendored as-is instead of reconverted.

That means the practical path is:

1. For retrieval models, start from the upstream Qwen Hugging Face repo and convert into MLX locally.
2. For text and visual models, vendor the already-MLX repos directly into `AppResources/LocalModels`.
3. Smoke test the local artifacts on-device.
4. Keep the final app bundle fully self-contained.

## Conceptual model

There are three layers involved here:

### 1. Conversion

`mlx_embeddings.convert` rewrites the upstream safetensors/config/tokenizer bundle into the MLX layout and can quantize the weights as part of that same step.

This is an artifact transformation step for embedding-style MLX models.

### 2. Embedding runtime

For embedding models, the runtime we want is `mlx_embeddings` on Python and `MLXEmbedders` on Swift.

The important part is that the converted model still advertises `model_type: "qwen3"` in `config.json`, because that is what the Swift and Python MLX embedder registries use to select the Qwen3 embedding implementation.

### 3. Reranker runtime

The reranker is structurally still a Qwen3 causal model, but the official Qwen usage does not consume a pooled embedding. It scores the prompt by looking at the final-token preference between `"yes"` and `"no"`.

So our reranker smoke test validates the real ranking behavior:

- format the pair exactly as Qwen documents it
- run one decode step
- read the next-token distribution
- compare the `"yes"` probability against the `"no"` probability

That gives us a real reranker signal instead of a weaker “model loaded” check.

## Repo layout

- `scripts/convert_embedding.sh`: convert and optionally upload the embedding model with `mlx_embeddings.convert`
- `scripts/convert_reranker.sh`: convert and optionally upload the reranker model with `mlx_embeddings.convert`
- `scripts/vendor_text_model.sh`: clone and sync the bundled big and small text models into `AppResources/LocalModels`
- `scripts/vendor_visual_model.sh`: clone and sync the bundled visual model into `AppResources/LocalModels/gemma-4-e2b-it-4bit`
- `scripts/smoke_test_embedding.py`: embedding similarity sanity check
- `scripts/smoke_test_reranker.py`: reranker yes/no scoring sanity check

## Step by step

### 1. Create the local environment

```bash
cd MLXConversion
make venv
make install
```

The wrapper scripts auto-detect either `.venv` or `venv`.

If you want to upload converted artifacts back to Hugging Face, log in first:

```bash
cd MLXConversion
venv/bin/hf auth login
```

### 2. Convert the embedding model

This defaults to a 4-bit local output at `models/Qwen3-Embedding-0.6B-4bit`.

```bash
cd MLXConversion
make convert-embedding
```

Optional environment variables:

- `SOURCE_REPO`: source Hugging Face repo, default `Qwen/Qwen3-Embedding-0.6B`
- `OUTPUT_DIR`: local output directory, default `models/Qwen3-Embedding-0.6B-4bit`
- `Q_BITS`: quantization bits, default `4`
- `Q_MODE`: quantization mode, default `affine`
- `Q_GROUP_SIZE`: quantization group size, default converter default
- `UPLOAD_REPO`: Hugging Face target repo for upload, omitted by default

Example with upload:

```bash
cd MLXConversion
UPLOAD_REPO=your-org/Qwen3-Embedding-0.6B-4bit-MLX make convert-embedding
```

Example matching the public `mxfp8` style:

```bash
cd MLXConversion
Q_BITS=8 Q_MODE=mxfp8 ./scripts/convert_embedding.sh
```

### 3. Smoke test the embedding model

This loads the converted artifact with `mlx_embeddings`, generates embeddings for a tiny query/document set, and asserts that the semantically relevant document scores above the irrelevant one.

```bash
cd MLXConversion
make smoke-embedding
```

If you want to point at a different model path or repo:

```bash
cd MLXConversion
venv/bin/python ./scripts/smoke_test_embedding.py --model mlx-community/Qwen3-Embedding-0.6B-mxfp8
```

### 4. Convert the reranker model

This defaults to a 4-bit local output at `models/Qwen3-Reranker-0.6B-4bit`.

```bash
cd MLXConversion
make convert-reranker
```

Optional environment variables:

- `SOURCE_REPO`: source Hugging Face repo, default `Qwen/Qwen3-Reranker-0.6B`
- `OUTPUT_DIR`: local output directory, default `models/Qwen3-Reranker-0.6B-4bit`
- `Q_BITS`: quantization bits, default `4`
- `Q_MODE`: quantization mode, default `affine`
- `Q_GROUP_SIZE`: quantization group size, default converter default
- `UPLOAD_REPO`: Hugging Face target repo for upload, omitted by default

### 5. Smoke test the reranker

This validates the official Qwen reranker behavior. It formats a query/document pair, runs a single decode step, and checks that the relevant document gets a higher `"yes"` probability than an irrelevant document.

```bash
cd MLXConversion
make smoke-reranker
```

You can also target a hosted MLX repo:

```bash
cd MLXConversion
venv/bin/python ./scripts/smoke_test_reranker.py --model mlx-community/Qwen3-Reranker-0.6B-mxfp8
```

### 6. Vendor the bundled text model

This clones the public MLX repo and syncs it into the exact folder name the app already loads at runtime.

```bash
cd MLXConversion
make vendor-text
```

Optional environment variables:

- `SOURCE_REPO`: source Hugging Face repo. If unset, both text models are vendored.
- `OUTPUT_DIR`: output directory for a single-model override.
- `TEMP_DIR`: temporary clone directory for a single-model override.

### 7. Vendor the bundled visual model

This clones the public MLX repo and syncs it into the exact folder name the app already loads at runtime.

```bash
cd MLXConversion
make vendor-visual
```

Optional environment variables:

- `SOURCE_REPO`: source Hugging Face repo, default `mlx-community/gemma-4-e2b-it-4bit`
- `OUTPUT_DIR`: output directory, default `../AppResources/LocalModels/gemma-4-e2b-it-4bit`
- `TEMP_DIR`: temporary clone directory, default `tmp/gemma-4-e2b-it-4bit`

### 8. CI bundling workflow

The app bundle still ships the vendored model directories from `AppResources/LocalModels`, but the large generated binaries should not live in Git history.

- keep the folder reference in Xcode so whatever is present under `AppResources/LocalModels` is copied into the app bundle
- keep the oversized generated files ignored in Git
- hydrate the text and visual models before `xcodebuild` in CI with `scripts/hydrate_bundled_models.sh`

That gives us a self-contained app bundle without making the repository itself carry multi-GB model payloads.

## What success looks like

After the smoke tests pass and the bundled repos are vendored into `AppResources/LocalModels`, we have high confidence in five things:

1. the converted MLX artifacts load on Apple Silicon
2. the embedding model produces usable retrieval vectors
3. the reranker model produces usable yes/no relevance scores
4. the text and visual models can load without any runtime network dependency
5. the output format is suitable for TaskTrace integration and bundling

## Notes for TaskTrace integration

The app runtime now loads all four models from local directories inside the bundle:

- `AppResources/LocalModels/Qwen3-Embedding-0.6B-4bit`
- `AppResources/LocalModels/Qwen3-Reranker-0.6B-4bit`
- `AppResources/LocalModels/Qwen3.5-4B-OptiQ-4bit`
- `AppResources/LocalModels/Qwen3.5-0.8B-OptiQ-4bit`
- `AppResources/LocalModels/gemma-4-e2b-it-4bit`

## References

- Qwen embedding model: `https://huggingface.co/Qwen/Qwen3-Embedding-0.6B`
- Qwen reranker model: `https://huggingface.co/Qwen/Qwen3-Reranker-0.6B`
- Qwen3.5 base model provenance: `https://huggingface.co/Qwen/Qwen3.5-4B-Base`
- Small Qwen3.5 MLX text model: `https://huggingface.co/mlx-community/Qwen3.5-0.8B-OptiQ-4bit`
- MLX Swift porting doc: `https://swiftpackageindex.com/ml-explore/mlx-swift-lm/main/documentation/mlxlmcommon/porting`
- MLX community org: `https://huggingface.co/mlx-community`
- Existing MLX embedding conversion: `https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-mxfp8`
- Existing MLX reranker conversion: `https://huggingface.co/mlx-community/Qwen3-Reranker-0.6B-mxfp8`
