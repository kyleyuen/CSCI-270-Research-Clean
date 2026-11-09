#!/bin/bash
# Build the original libpostal parser and the optimized (experiment 203) parser side by side.
# macOS, Apple Silicon, bash 3.2.   usage: build/build.sh MODEL_DIR OUT_DIR [UPSTREAM_DIR]
#   MODEL_DIR     libpostal v1.0.0 data (contains address_parser/, numex/, ...). Checked against build/MODEL_FILES.sha256.
#   OUT_DIR       everything is written here (upstream checkout, builds, bin/). Nothing is written elsewhere.
#   UPSTREAM_DIR  optional; default OUT_DIR/libpostal, cloned from $UPSTREAM_URL and pinned to the commit below.
# Result: OUT_DIR/bin/original/{dump_outputs,bench_ext,fuzz_pipeline} and OUT_DIR/bin/optimized/{same three}.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { sed -n 2,7p "$0"; exit 2; }
MODEL="$(cd "$1" && pwd)"; mkdir -p "$2"; W="$(cd "$2" && pwd)"; UP="${3:-$W/libpostal}"
COMMIT=25099c506612b34b23b1bfe286ca6321fcf06f35
MIMALLOC="$(brew --prefix mimalloc)/lib/mimalloc.o"; [ -f "$MIMALLOC" ] || { echo "mimalloc.o not found (brew install mimalloc)"; exit 1; }
mkdir -p "$W/data" "$W/bin/original" "$W/bin/optimized"
ln -sfn "$MODEL" "$W/data/libpostal"
( cd "$W/data/libpostal" && shasum -a 256 -c "$HERE/build/MODEL_FILES.sha256" >/dev/null ) || { echo "model files differ from the ones used for every result"; exit 1; }

echo "1/3 upstream libpostal $COMMIT"
[ -d "$UP/.git" ] || git clone -q "${UPSTREAM_URL:-https://github.com/openvenues/libpostal.git}" "$UP"
git -C "$UP" checkout -q $COMMIT
SRC="$UP/src"
if [ ! -f "$SRC/.libs/libpostal.a" ]; then   # same configuration as the original baseline
  ( cd "$UP" && ./bootstrap.sh && ./configure --disable-data-download --disable-sse2 --datadir="$W/data" && make -C src -j"$(sysctl -n hw.ncpu)" libpostal.la ) > "$W/upstream_build.log" 2>&1
fi

echo "2/3 original harnesses"
for h in bench_ext dump_outputs fuzz_pipeline; do clang -O2 -g -I"$SRC" "$HERE/harness/$h.c" "$SRC/.libs/libpostal.a" -lm -o "$W/bin/original/$h"; done

echo "3/3 optimized library (-O2, LTO, PGO from build/dev.profdata, -O1 tokenizer, mimalloc)"
X="-fprofile-instr-use=$HERE/build/dev.profdata -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date"
BASE="-std=gnu2x -DHAVE_CONFIG_H -Wall -Wno-unused-function -Wno-unused-parameter -Wformat -Werror=format-security -Winit-self -Wno-sign-compare -g -D LIBPOSTAL_EXPORTS"
SW="-DEXP_NO_RESET -DEXP_DEDUP_BATCH -DEXP_FEATURE_DICT -DEXP_DIRECT_KEYS -DEXP_WEIGHT_PREFETCH -DEXP_LEAN_CONTEXT -DEXP_VOCAB_DICT -DEXP_ASCII_NORM -DEXP_ADMIN_SHARE -DEXP_FAST_APPEND -DEXP_FAST_JOIN -DEXP_VOCAB_MEMO -DEXP_INT_KEYS -DEXP_TRANS_SKIP -DEXP_NORM_TABLE -DEXP_CANON_CONST -DEXP_RESPONSE_BLOCK -DEXP_REUSE -DEXP_VITERBI_NEON -DEXP_TOKEN_ASCII -DEXP_FD_INLINE -DEXP_NAME_LEN -DEXP_NORM_HANGUL -DEXP_ROW_PACK -DEXP_ROLE_IDS -DEXP_WORD_MEMO -DEXP_WM_CANON -DEXP_CONST_IDS -DEXP_ST_ROW0 -DEXP_LOADF=3 -DEXP_VITERBI20 -DEXP_TRANS_ALIAS -DEXP_PC_COMPRESS -DEXP_FTT -DEXP_FTT_ROLE_PREFETCH -DEXP_NAME_BYTE -DEXP_LETTERS_FAST -DEXP_FA_LEN -DEXP_DIGITS_FAST -DEXP_FTT_PF1 -DEXP_FTT_PF2 -DEXP_PC_PREFETCH -DEXP_VITERBI_MAXONLY -DEXP_VITERBI_FMAX -DEXP_NORM_PAIR -DEXP_PS_FLAGS -DEXP_ROW_LINES=8 -DEXP_ROW_STEP=128 -DEXP_ROW_TRANS_ONLY -DEXP_CP_IDS"
CHANGED="crf trie string_utils address_parser features trie_search transliterate normalize crf_context libpostal tokens"
LIBSRC="strndup libpostal expand address_dictionary transliterate tokens trie trie_search trie_utils string_utils file_utils utf8proc/utf8proc normalize numex features unicode_scripts address_parser address_parser_io averaged_perceptron crf crf_context sparse_matrix averaged_perceptron_tagger graph graph_builder language_classifier language_features logistic_regression logistic minibatch float_utils ngrams place near_dupe double_metaphone geohash/geohash dedupe string_similarity acronyms soft_tfidf jaccard"
DD="-DLIBPOSTAL_DATA_DIR=\"$W/data/libpostal\""
D="$W/build"; rm -rf "$D"; mkdir -p "$D/src" "$D/obj"
for f in $CHANGED; do cp "$HERE/sources/$f.c" "$D/src/"; done; cp "$HERE/sources/"*.h "$D/src/"
for f in $LIBSRC; do b=$(basename $f); case " $CHANGED " in *" $b "*) S="$D/src/$b.c";; *) S="$SRC/$f.c";; esac
  ( cd "$SRC" && clang $BASE $SW -O2 -flto $X "$DD" -I"$D/src" -I"$SRC" -I"$SRC/.." -c "$S" -o "$D/obj/$(echo $f | tr / _).o" ); done
( cd "$SRC" && clang $BASE -O1 "$DD" -I"$SRC" -I"$SRC/.." -c "$SRC/scanner.c" -o "$D/obj/scanner.o" && clang $BASE -O1 -I"$SRC" -I"$SRC/.." -c "$SRC/klib/drand48.c" -o "$D/obj/drand48.o" )
( cd "$D/obj" && ar -rc ../libpostal.a *.o && ranlib ../libpostal.a )
for h in bench_ext dump_outputs fuzz_pipeline; do clang -O2 -g -flto $X -I"$SRC" "$MIMALLOC" "$HERE/harness/$h.c" "$D/libpostal.a" -lm -o "$W/bin/optimized/$h"; done
echo "built: $W/bin/original and $W/bin/optimized"
