#!/bin/bash

# Put the exact local builds ahead of the online repositories, so pacman can
# resolve their dependency closure without substituting published packages.
set -euo pipefail

if (( $# < 5 )); then
  echo "Usage: prepare-local-repo.sh <mirror-dir> <repo-dir> <online-config> <output-config> <package>..." >&2
  exit 1
fi

mirror_dir=$1
repo_dir=$2
online_config=$3
output_config=$4
shift 4

mkdir -p "$repo_dir"
local_packages=()
for package_name in "$@"; do
  package_file=""
  for candidate in "$mirror_dir/$package_name-"*.pkg.tar.*; do
    [[ -f $candidate && $candidate != *.sig ]] || continue
    read -r candidate_name _ < <(pacman -Qp "$candidate" 2>/dev/null) || continue
    [[ $candidate_name == "$package_name" ]] || continue
    if [[ -n $package_file ]]; then
      echo "ERROR: multiple local builds found for $package_name" >&2
      exit 1
    fi
    package_file=$candidate
  done
  if [[ -z $package_file ]]; then
    echo "ERROR: local build not found for $package_name" >&2
    exit 1
  fi
  ln -sf "$package_file" "$repo_dir/${package_file##*/}"
  local_packages+=("$repo_dir/${package_file##*/}")
done

repo-add "$repo_dir/omarchy-local.db.tar.gz" "${local_packages[@]}"

# Preserve the online options, inserting the local repository before the first
# network repository. Repository order, not pkgver, makes local builds win.
awk -v repo_dir="$repo_dir" '
  /^\[/ && $0 != "[options]" && !inserted {
    print "[omarchy-local]"
    print "SigLevel = Never"
    print "Server = file://" repo_dir
    print ""
    inserted = 1
  }
  { print }
' "$online_config" > "$output_config"
