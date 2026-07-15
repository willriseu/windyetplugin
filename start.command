#!/bin/bash
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if ! command -v npm >/dev/null 2>&1; then
  echo "HIBA: npm nincs telepitve. Telepitsd a Node.js-t."
  read -r -p "Enter a bezarashoz..."
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "Fuggosegek telepitese..."
  npm install || { read -r -p "npm install hiba. Enter..."; exit 1; }
fi

rm -rf dist
mkdir -p dist
npm start
