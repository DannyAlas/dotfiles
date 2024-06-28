#!/bin/bash

url="https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json"

file="$HOME/.config/styles/catppuccin.json"

mkdir -p "$(dirname "$file")"

curl -sL "$url" -o "$file"

sed -i 's/"name":"accentColor","value":null/"name":"accentColor","value":"lavender"/g' "$file"
