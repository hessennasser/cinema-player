#!/bin/zsh
set -euo pipefail

# Publishes Website/ to the gh-pages branch used by GitHub Pages.
# Run after changing the marketing site:
#   zsh Scripts/publish-site.sh

project_dir="${0:A:h:h}"
cd "$project_dir"

git subtree push --prefix=Website origin gh-pages
