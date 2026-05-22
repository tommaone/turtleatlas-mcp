#!/usr/bin/env bash
set -euo pipefail

echo "==> Initializing knowledge base from template..."

if [ -d "resources" ] && [ "$(ls -A resources 2>/dev/null)" ]; then
  echo "  resources/ already exists and is not empty — skipping copy."
  echo "  Remove it first if you want a fresh start:  rm -rf resources"
  exit 1
fi

cp -r template/resources .
echo "  Copied template/resources/ → resources/"
echo ""
echo "Done. Now fill in your actual data:"
echo "  resources/table_overview.json   — table metadata"
echo "  resources/tables.zip             — full schema JSONs per table"
echo "  resources/general_db_info.md     — SQL dialect rules"
echo "  resources/experts/               — domain expert knowledge files"
echo "  resources/journeys/              — business process journeys"