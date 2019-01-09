#!/bin/sh
username="${1:-"user"}"
groupname="${2:-"user"}"
app_dir="${3:-"/app"}"
src_dir="$(cat DIBS_DIR_SRC)"
rm -rf "$app_dir"
cp -a "$src_dir" "$app_dir"
rm -rf "$app_dir/local"
mkdir -p "$app_dir/.profile.d"
cat >"$app_dir/.profile" <<'END'
#!/bin/sh
for f in "$HOME/.profile.d"/*.sh ; do
   . "$f"
done
END
chown -R "$USERNAME:$USERNAME" "$app_dir"
