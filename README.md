# libpostal address-parser speedup: source changes only

The optimized (experiment 203, "CPI") address parser, as the changed files only. No datasets, experiment logs, binaries or benchmark outputs.

Base: [openvenues/libpostal](https://github.com/openvenues/libpostal) at commit `25099c506612b34b23b1bfe286ca6321fcf06f35` (MIT). This repo does not vendor it.

## Contents

`sources/` holds the 16 files, meant to replace or be added to libpostal's `src/`:

- 12 modified upstream files: `address_parser.c`, `crf.c`, `crf.h`, `crf_context.c`, `features.c`, `libpostal.c`, `normalize.c`, `string_utils.c`, `transliterate.c`, `trie.c`, `trie.h`, `trie_search.c`.
- 3 new headers: `feature_dict.h`, `stream_postcode_graph.h`, `fa_nb.h`.
- `tokens.c`, identical to upstream. The build script lists it, so it is kept.

Most changes sit behind `EXP_*` compile switches (`build/BUILD_SWITCHES.txt`).

`harness/` holds the three small test programs (`dump_outputs.c`, `bench_ext.c`, `fuzz_pipeline.c`).

`build/` holds the build: `build.sh` (builds original and optimized side by side), `compare.sh` (checks byte-identical output), the PGO profile `dev.profdata`, and checksums for the sources (`SOURCE_MANIFEST.sha256`) and model files (`MODEL_FILES.sha256`). `BUILD.md`, `BUILD_SWITCHES.txt` and `build_cc.sh` are the original build record; `build_cc.sh` has hard-coded paths from the old workspace, so use `build.sh` instead.

## Run it

Needs macOS on Apple Silicon, clang, autotools and `brew install mimalloc`, plus the libpostal v1.0.0 model data.

```sh
build/build.sh /path/to/libpostal-model-data /path/to/work-dir   # clones upstream at the pinned commit, builds both
build/compare.sh /path/to/work-dir addresses.txt                 # PASS = byte-identical output
```

Check the sources: `shasum -a 256 -c build/SOURCE_MANIFEST.sha256`

## Result (from the full research repo)

On one Apple Silicon Mac, warm parsing is 5.5-6.1x faster than original libpostal on one thread, with byte-identical output on 130,341 tested addresses and lower peak memory. Startup is about 6.9 s slower. The full evidence, datasets and experiment history are in the original research repository.

The optimized build uses profile-guided optimization trained on one dataset (golden-v1) and links mimalloc.
