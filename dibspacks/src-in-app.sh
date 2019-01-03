#!/bin/sh
rm -rf /app
cp -a "$(cat DIBS_DIR_SRC)" /app
rm -rf /app/local
mkdir -p /app/.profile.d
cat >/app/.profile <<'END'
#!/bin/sh
for f in "$HOME/.profile.d"/*.sh ; do
   . "$f"
done
END
#chown -R user:user /app/.profile /app/.profile.d
chown -R user:user /app
