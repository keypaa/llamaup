# GPU Substring Matching Logic

## Overview

The `llamaup` toolchain uses substring matching to map GPU model names (from `nvidia-smi`) to their corresponding SM (Streaming Multiprocessor) versions defined in `configs/gpu_map.json`.

## How It Works

### Longest Match Strategy

The `lookup_sm()` function in `scripts/detect.sh` uses a **longest match** strategy to handle overlapping patterns correctly:

1. **Collect all matches**: For a given GPU name, find all patterns in `gpu_map.json` that are substrings of that GPU name
2. **Pick the longest**: Select the pattern with the most characters (most specific)
3. **Return SM version**: Return the SM version associated with that pattern

### Example

Given these entries in `gpu_map.json`:
```json
{
  "sm_75": {
    "gpus": ["GTX 1650", "GTX 1650 Super", "GTX 1660"]
  }
}
```

When matching `"NVIDIA GeForce GTX 1650 SUPER"`:
- Both `"GTX 1650"` (9 chars) and `"GTX 1650 Super"` (15 chars) match
- **Winner**: `"GTX 1650 Super"` (longer/more specific)

This ensures that more specific GPU models are correctly identified, even when more generic patterns also match.

## Pattern Validation

The `validate_gpu_map()` function checks for overlapping patterns across **different SM families**:

```bash
LLAMA_VALIDATE_GPU_MAP=1 ./scripts/detect.sh
```

This will print warnings if:
- Pattern A from SM family X is a substring of Pattern B from SM family Y
- This could indicate a misconfiguration in `gpu_map.json`

### Example Warning

```
[WARNING] GPU pattern overlap detected:
  'RTX 4000' (SM 75) is a substring of 'RTX 4000 Ada' (SM 89)
  This may cause ambiguous matches. Consider using more specific patterns.
```

## Best Practices for Adding GPUs

1. **Use specific patterns**: Prefer `"RTX 6000 Ada"` over just `"RTX 6000"`
2. **Include generation markers**: `"RTX 2000 Ada"`, `"RTX 3090"`, etc.
3. **Order doesn't matter**: With longest-match logic, you don't need to worry about pattern order
4. **Test your additions**: Run `LLAMA_VALIDATE_GPU_MAP=1 ./scripts/detect.sh` after editing

## Edge Cases Handled

### Multi-word patterns
- `"Quadro RTX 8000"` correctly matches even when nvidia-smi returns `"Quadro RTX 8000 Mobile"`

### Case insensitivity
- Pattern `"rtx 4090"` matches `"NVIDIA GeForce RTX 4090"`
- All matching is case-insensitive

### Model suffixes
- `"L40S"` and `"L40"` are distinct patterns
- `"L40S"` (4 chars) wins over `"L40"` (3 chars) when GPU name contains "L40S"

### Similar model names
- `"GTX 1650 Super"` vs `"GTX 1650"` → longest wins
- `"RTX A6000"` vs `"RTX 6000 Ada"` → different patterns, no conflict

## Testing

Run the test suite to verify matching logic:

```bash
./scripts/test_gpu_matching.sh
```

This tests:
- Correct SM mapping for various GPU models
- Longest-match priority
- Pattern overlap detection

## Implementation Details

### Function: `lookup_sm()`

**Location**: `scripts/detect.sh:220`

**Algorithm**:
```bash
1. Convert GPU name to lowercase
2. For each pattern in gpu_map.json:
   a. Convert pattern to lowercase
   b. Check if pattern is substring of GPU name
   c. If yes, record pattern length and SM version
3. Return SM with longest matching pattern
```

**Time complexity**: O(n × m) where n = number of GPU patterns, m = avg pattern length

### Function: `validate_gpu_map()`

**Location**: `scripts/detect.sh:156`

**Algorithm**:
```bash
1. Extract all patterns with their SM versions
2. For each pair of patterns (i, j):
   a. Check if pattern_i is substring of pattern_j
   b. If yes AND they have different SMs, print warning
3. Continue validation (doesn't exit on warnings)
```

**When it runs**: Only when `LLAMA_VALIDATE_GPU_MAP=1` or `LLAMA_DEPLOY_DEBUG=1`

## Troubleshooting

### My GPU isn't detected correctly

1. Run `nvidia-smi` and check the exact GPU name
2. Run `LLAMA_DEPLOY_DEBUG=1 ./scripts/detect.sh --json` to see what's detected
3. Check if a pattern exists in `configs/gpu_map.json` that should match
4. If needed, add a more specific pattern

### Pattern overlap warnings appear

This is informational. As long as you're using the longest-match logic (post-2025 versions), overlaps across different SM families are handled correctly. However, consider making patterns more specific to avoid confusion.

### Wrong SM version detected

This likely means:
1. A more generic pattern matched instead of a specific one (fixed by longest-match)
2. The GPU is not in `gpu_map.json` (add it!)
3. Multiple patterns with the same length match (rare - add differentiating suffix)

## Migration Notes

### Pre-longest-match behavior (before 2025-02-21)

Old behavior used **first match**:
- Order in `gpu_map.json` mattered
- `"GTX 1650"` before `"GTX 1650 Super"` → wrong match for "GTX 1650 Super"

### Current behavior (longest-match)

New behavior uses **longest match**:
- Order in `gpu_map.json` doesn't matter
- Most specific pattern always wins
- Backward compatible with existing configurations
