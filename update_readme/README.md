# update-readme

### Descriptions

**Decide where descriptions live**

Each folder needs a way to tell the script "what am I about?"
Two common approaches:

- `DESCRIPTION` file inside each folder (plain text, oneliner)
- Or: first line of `README.md` inside each folder.

### Script

Here the python script `update_readme.py` scans the repo, grabs folder names + descriptions and injects them into `README.md`

### Markers in README

Edit README.md to include markers where the list should appear

```markdown
# Script Repo

This repo has a bunch of useful scripts

## Script folders

<!-- FOLDER-LIST-START -->
<!-- FOLDER-LIST-END -->

Descriptions auto-generated from each folder's `DESCRIPTION file`
```

### Update workflow

- Run manually :

```bash
python3 update_readme.py
```

- Or add a git pre-commit hook so it auto-runs before every commit

```bash
echo "python3 update_readme.py && git add README.md" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

- Or set up a Github Action to regenerate on every push.
