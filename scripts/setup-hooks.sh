#!/bin/bash
# Setup git hooks for the repository

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "🔧 Setting up git hooks..."

# Configure git to use custom hooks directory
git config core.hooksPath .githooks

# Make hooks executable
chmod +x "$REPO_ROOT/.githooks/"*

echo "✅ Git hooks configured!"
echo ""
echo "Hooks installed:"
ls -la "$REPO_ROOT/.githooks/"
echo ""
echo "To disable hooks temporarily, use: git push --no-verify"
