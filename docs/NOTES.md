# llamaup — Learning Notes & Progress

A running log of what we've built, what's left, and what bash concepts came up along the way.

---

## Progress

| Task | File | Status |
|------|------|--------|
| 1 | `configs/gpu_map.json` | ✅ Done |
| 2 | `scripts/detect.sh` | ✅ Done |
| 3 | `scripts/build.sh` | ✅ Done |
| 4 | `scripts/pull.sh` | ✅ Done |
| 5 | `scripts/verify.sh` | ✅ Done |
| 6 | `scripts/list.sh` | ✅ Done |
| 7 | `.github/workflows/build.yml` | ✅ Done |
| 8 | `CONTRIBUTING.md` | ✅ Done |
| 9 | Issue templates | ✅ Done |
| 10 | `LICENSE` | ✅ Done |

---

## Discoveries

### Why `jq` is everywhere in this project
`jq` is a command-line JSON processor (like `sed`/`awk` but for JSON). Since
`gpu_map.json` is read by every script, `jq` is a core dependency. Key patterns
used in this project:

```bash
# Read a field
jq -r '.gpu_families.sm_89.sm' configs/gpu_map.json
# → 89

# Iterate over all families
jq -r '.gpu_families | keys[]' configs/gpu_map.json
# → sm_100, sm_101, sm_120, sm_75, sm_80, sm_86, sm_89, sm_90

# Case-insensitive substring search across GPU names (used in detect.sh)
jq -r --arg name "NVIDIA L40S" '
  .gpu_families | to_entries[] |
  select(.value.gpus[] | ascii_downcase | inside($name | ascii_downcase)) |
  .value.sm
' configs/gpu_map.json
# → 89
```

`-r` means "raw output" — strips the surrounding quotes from strings. Without
it, `jq` outputs `"89"` (with quotes), which would break variable assignments.

---

## Bash Concepts

### `set -euo pipefail` — the safety net every script opens with

Every script starts with this. Here's what each part does:

| Option | Meaning |
|--------|---------|
| `-e` | **Exit immediately** if any command returns a non-zero exit code. Without this, scripts silently continue after errors. |
| `-u` | **Treat unset variables as errors.** Without this, a typo like `$VERSIN` silently expands to an empty string. |
| `-o pipefail` | **Fail if any command in a pipeline fails.** Without this, `bad_cmd \| grep foo` would succeed because `grep` succeeded — the pipe's exit code is only the *last* command. |

Example of why `-o pipefail` matters:
```bash
# Without pipefail: exit code = 0 (because grep succeeds on empty input)
cat nonexistent_file.txt | grep "something"

# With pipefail: exit code = 1 (cat failed, and that propagates)
```

---

### `${BASH_SOURCE[0]}` — how scripts find themselves

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

This is how every script resolves its own absolute path so it works regardless
of where you call it from. Breaking it down:

- `${BASH_SOURCE[0]}` — the path used to invoke this script (e.g. `./scripts/detect.sh` or `/home/user/llamaup/scripts/detect.sh`)
- `dirname ...` — strips the filename, leaving just the directory portion
- `cd ... && pwd` — the `cd` resolves any relative parts (`..`, symlinks); `pwd` then returns the clean absolute path
- The outer `$()` is **command substitution** — it runs the inner commands in a subshell and captures stdout as a string

Why not just `SCRIPT_DIR=$(dirname $0)`? Two reasons:
1. `$0` can be unreliable when a script is *sourced* (called with `.` or `source`) vs executed — `${BASH_SOURCE[0]}` always refers to the script file itself
2. `dirname $0` gives a relative path like `./scripts`; the `cd && pwd` trick makes it absolute

---

### Sourcing vs executing a script

```bash
# Execute (runs in a child process — variables/functions don't leak back)
./scripts/detect.sh

# Source (runs in the current shell — functions and variables are imported)
# shellcheck source=scripts/detect.sh
source "${SCRIPT_DIR}/detect.sh"
```

`build.sh` and `pull.sh` *source* `detect.sh` to reuse its `lookup_sm()` and
`detect_cuda_version()` functions without duplicating code. The `shellcheck`
comment above the source line is how you tell shellcheck where to find the
sourced file so it can lint it properly (otherwise it warns about undefined functions).

---

### `local` — variable scoping in functions

```bash
my_function() {
  local result
  result="hello"
  echo "$result"
}
```

In bash, **all variables are global by default** — there's no automatic function
scope like in Python or JS. `local` makes a variable scoped to the function.
Without it, setting `result="hello"` inside a function would overwrite any
`result` variable in the calling scope.

Convention in this project: always declare `local` variables at the top of a
function, one per line. This makes the function's "signature" visible at a glance.

---

### `local var` vs `local var=$(command)` — a subtle gotcha

```bash
# WRONG — masks exit code!
local sm=$(lookup_sm "$gpu_name" "$gpu_map")

# CORRECT — declare and assign separately
local sm
sm=$(lookup_sm "$gpu_name" "$gpu_map")
```

When you do `local var=$(command)`, the exit code of `command` is **discarded**
because `local` itself returns 0. If `set -e` is active and the command fails,
the script won't exit — the failure is swallowed. This is one of the most common
bash bugs and what `shellcheck` catches with SC2155.

---

### Exit codes and `||`

```bash
command || { echo "Error: command failed"; exit 1; }
```

The `||` (OR) operator runs the right side only if the left side fails (non-zero
exit code). This is how error handling without `if/then/fi` blocks works in bash.
The `{ ...; }` groups multiple commands together — note the required semicolon
before `}` and the space after `{`.

---

---

### `command -v` — checking if a tool is installed

```bash
command -v nvidia-smi >/dev/null 2>&1 || missing+=("nvidia-smi")
```

`command -v <name>` returns the path of the tool if it's in `$PATH`, or exits
non-zero if it's not found. It's the portable bash way to check for a program
(prefer it over `which` which behaves differently across distros).

`>/dev/null 2>&1` silences both stdout (`>`) and stderr (`2>&`1). We don't want
the path printed during a deps check — we just want the exit code.

---

### Arrays in bash

```bash
local missing=()
 missing+=("nvidia-smi")
missing+=("jq")
echo "${missing[*]}"   # all elements space-separated
echo "${#missing[@]}"  # number of elements
```

Bash arrays are declared with `()` and appended to with `+=()`. Note the
differences:

| Syntax | Meaning |
|--------|---------|
| `${arr[*]}` | All elements as a single string (space-separated) |
| `${arr[@]}` | All elements as separate words (preserves spaces in elements) |
| `${#arr[@]}` | Count of elements |
| `${arr[$i]}` | Element at index `i` |

Always prefer `"${arr[@]}"` (quoted) when iterating — it handles elements that
contain spaces correctly.

---

### `while IFS= read -r` — safely reading multi-line output

```bash
while IFS= read -r gpu_name; do
  # process $gpu_name
done <<< "$gpu_names_raw"
```

This is the idiomatic bash way to loop over lines:

- `IFS=` — sets the field separator to nothing for this `read` call, so
  leading/trailing whitespace in lines is preserved
- `read -r` — raw mode: backslashes are treated literally (not as escape chars)
- `<<< "$var"` — a **here-string**: feeds the value of a variable as stdin to
  the command on the left. It's a one-liner version of `echo "$var" | ...`

The alternative `< <(command)` is a **process substitution** — it runs a
command and feeds its output as a file descriptor:

```bash
while IFS='|' read -r sm gpu; do
  ...
done < <(jq -r '...' gpu_map.json)
```

Crucial difference: using `command | while read` creates a *subshell* for the
loop body, so variables set inside it are lost after the loop ends. The
`< <(...)` form avoids the subshell, keeping variable assignments visible in
the outer scope.

---

### `[[ ]]` vs `[ ]` — prefer double brackets in bash

```bash
if [[ "$gpu_name_lower" == *"$candidate_lower"* ]]; then
```

`[[ ]]` is bash-specific and safer than POSIX `[ ]`:
- Glob patterns like `*` work unquoted on the *right* side of `==`
- No word-splitting or glob expansion on variables (no need to over-quote)
- Supports `&&` and `||` inside the brackets
- `=~` for regex matching

The pattern `*"$var"*` checks if `$var` is a **substring** — the `*` wildcards
match anything before and after.

---

### The `BASH_SOURCE[0] == $0` guard — sourcing safety

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

This is how `detect.sh` can be both a standalone script *and* a library.

- When you run `./scripts/detect.sh`, `${BASH_SOURCE[0]}` and `$0` are the
  same path, so `main` runs.
- When `build.sh` does `source "${SCRIPT_DIR}/detect.sh"`, `${BASH_SOURCE[0]}`
  is `detect.sh` but `$0` is `build.sh` — the condition is false, so only the
  functions are imported without running `main`.

`"$@"` passes all command-line arguments from the calling context through to
`main` unchanged.

---

### `nproc` and default values with `$(...)`

```bash
local build_jobs
build_jobs=$(nproc 2>/dev/null || echo "4")
```

`nproc` returns the number of CPU cores. The `|| echo "4"` is a fallback —
if `nproc` isn't available (some minimal containers), the default is 4.
`2>/dev/null` silences any error output from `nproc`.

---

### `case` statement — bash's switch

```bash
case "$1" in
  --sm)      sm_version="$2" ; shift 2 ;;
  --dry-run) dry_run=true    ; shift   ;;
  -h|--help) usage ;;
  *)         error "Unknown option: $1" ;;
esac
```

`case` is how bash switches on string values. Key syntax:
- Each branch ends with `;;` (double semicolon)
- `|` means OR between patterns
- `*)` is the catch-all (like `default:` in other languages)
- `esac` closes the block (`case` backwards)

`shift` removes `$1` from the argument list, shifting everything left.
`shift 2` removes both `$1` and `$2` (used when consuming `--flag value` pairs).

---

### `<<EOF` heredoc — multi-line strings

```bash
cat <<EOF
Usage: build.sh [OPTIONS]

  --sm <version>    SM version to build for.
EOF
```

A heredoc feeds a multi-line string as stdin to a command. Everything between
`<<EOF` and the closing `EOF` (on its own line, at the start) is passed
literally. Variables are expanded unless you quote the delimiter: `<<'EOF'`.

Common uses: `usage()` functions, multi-line error messages, building JSON.

---

### Regex matching with `=~` and `BASH_REMATCH`

```bash
if [[ "$name" =~ llama-([^-]+)-linux-cuda([^-]+)-sm([0-9]+)-x64\.tar\.gz ]]; then
  local ver="${BASH_REMATCH[1]}"
  local cuda="${BASH_REMATCH[2]}"
  local sm="${BASH_REMATCH[3]}"
fi
```

`=~` inside `[[ ]]` matches a regex. Capture groups `(...)` are stored in
`BASH_REMATCH`: `[0]` is the full match, `[1]` is the first group, etc.

Key regex difference from most languages: **do not quote the pattern** —
`[[ "$str" =~ "$pattern" ]]` treats the right side as a literal string when
quoted. Leave it unquoted (or store in a variable) for real regex matching.

---

### `cut` and `awk` — extracting fields from strings

```bash
# Split on '|' and get the first field
asset_name=$(echo "$asset_info" | cut -d'|' -f1)

# Extract the first whitespace-delimited column
hash=$(sha256sum "$file_path" | awk '{print $1}')
```

- `cut -d'|' -f1` splits on delimiter `|` and returns field 1
- `awk '{print $1}'` prints the first space-separated token

`awk` is a full programming language, but in shell scripts it's mostly used
for its field-splitting (`$1`, `$2`, ...) and simple arithmetic.

---

### `jq` for building JSON in bash

```bash
json_gpus=$(jq -n \
  --argjson arr "$json_gpus" \
  --arg name "$gpu_name" \
  --arg sm "$sm" \
  '$arr + [{"name":$name,"sm":$sm}]')
```

Building JSON by string concatenation in bash is fragile (names with quotes
break everything). `jq -n` (null input) with `--arg`/`--argjson` flags lets
you pass shell variables into a jq expression safely:
- `--arg name "$var"` passes a string
- `--argjson arr "$json"` passes a pre-parsed JSON value

---

### `trap` — cleanup on exit (used internally by build.sh patterns)

```bash
trap 'rm -f /tmp/tmpfile' EXIT
```

`trap` registers a command to run when the script exits (even on error or
Ctrl-C). It's the bash equivalent of `finally` or a destructor. Common uses:
cleaning up temp files, printing a status message, restoring terminal state.

---

### GitHub Actions matrix strategy — how the CI works

In `.github/workflows/build.yml`, the `matrix` key lets one job definition
run multiple times with different inputs:

```yaml
strategy:
  matrix:
    include:
      - sm: "89"
        cuda_image: "12.4.0"
      - sm: "90"
        cuda_image: "12.4.0"
```

Each entry spawns a separate parallel job. Inside the job, values are accessed
as `${{ matrix.sm }}` and `${{ matrix.cuda_image }}`.

The dynamic matrix (built in `resolve-version` and passed via `outputs`) is
more advanced: it uses `fromJson()` to turn a JSON string output from one job
into a matrix for the next. This is how the optional `sm_versions` input
filters which builds to run.

---

*(Add new concepts here as we continue)*
