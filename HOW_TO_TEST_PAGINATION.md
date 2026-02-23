# How to Test Task 8 - Pagination

## Quick Test (Automated)
```bash
./test_pagination.sh
```
This runs automated checks to verify pagination code exists.

## Interactive Test (Manual)

### Test 1: Search with many results
```bash
./scripts/llama-models search llama
```
Expected behavior:
- Shows first 20 results
- Option #21 should be "── Show more ──"
- Option #22 should be "Quit"

### Test 2: Trigger pagination
```bash
# Search for a popular term
./scripts/llama-models search llama
```
When prompted:
1. Enter `21` to select "── Show more ──"
2. See "Loading more results..." message
3. Table should now show 40 models (first 20 + next 20)
4. Option #41 should be "── Show more ──" (if more results exist)
5. Option #42 should be "Quit"

### Test 3: Load multiple pages
```bash
./scripts/llama-models search qwen
```
Keep selecting "── Show more ──" option multiple times to verify:
- Results accumulate (20, 40, 60, etc.)
- "Show more" option disappears when no more results
- All models remain selectable after pagination

### Test 4: Verify last page behavior
```bash
./scripts/llama-models search "very-rare-specific-model-name"
```
Expected:
- If fewer than 20 results, no "Show more" option appears
- Only "Quit" option after the model list

## Verification Checklist

✅ First page shows exactly 20 results  
✅ "── Show more ──" appears as second-to-last option  
✅ Selecting "Show more" fetches next batch  
✅ Results accumulate (don't replace)  
✅ Numbering continues (21, 22, 23... not restarting at 1)  
✅ "Show more" disappears on last page  
✅ All accumulated models remain selectable  
✅ Download still works after pagination  

## Quick one-liner test
```bash
# Should show "1" (meaning "Show more" option exists)
echo "22" | timeout 30 ./scripts/llama-models search tinyllama 2>&1 | grep -c "── Show more ──"
```

## What to look for in output
```
Found 20 GGUF models:

#   Model ID                                Downloads   Variants
─────────────────────────────────────────────────────────────────────────────
1   Model A                                    100000         10
...
20  Model T                                     50000          5

Select a model to download:
 1) Model A
 ...
20) Model T
21) ── Show more ──    ← This is the key indicator!
22) Quit
```
