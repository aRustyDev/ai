# Cache Directory

This directory is for temporary files that should not be tracked in version control.

## Usage

Create project-specific subdirectories for any temporary files:

```bash
mkdir -p .claude/cache/tree-sitter-kvconf/
```

## What Goes Here

- Downloaded repositories for analysis
- Temporary test data
- Build artifacts during testing
- External resources that don't belong in the project

## Important

All contents of this directory are ignored by git. Do not put anything here that needs to be preserved.