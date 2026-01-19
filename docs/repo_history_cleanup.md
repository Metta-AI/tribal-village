# Repo History Cleanup

## Why This Exists
Large historical assets can make fresh clones very heavy even if the files
have been deleted on main. When the pack size creeps up, we should identify
and remove the culprits from history.

## Find the Largest Blobs
Run these in a fresh clone:

```bash
git rev-list --objects --all > /tmp/all-objects.txt
git cat-file --batch-check < /tmp/all-objects.txt \
  | sed -n 's/^\\([0-9a-f]*\\) blob \\([0-9]*\\) .*/\\2 \\1/p' \
  | sort -n -r | head -n 30
```

Then map hashes back to file paths:

```bash
git rev-list --objects --all | rg <hash>
```

## Remove History Entries (git-filter-repo)
Use `git filter-repo` to strip blobs or paths:

```bash
git filter-repo --strip-blobs-bigger-than 20M
# or
git filter-repo --path path/to/large/file --invert-paths
```

## Coordination Checklist
History rewrites require coordination:
- Announce the rewrite window.
- Force-push the rewritten main branch.
- Ask everyone to re-clone or hard reset to the new history.

## After the Rewrite
1) Update `.gitignore` if the culprit should never return.
2) Add checks or pre-commit hooks if needed (optional).
3) Confirm pack size in a fresh clone.
