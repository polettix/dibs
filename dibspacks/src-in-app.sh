#!/bin/sh
rm -rf /app
cp -a "$1" /app
rm -rf /app/local
mkdir -p /app/.profile.d
cat >/app/.profile <<END
#!/bin/sh
for f in "$HOME/.profile.d"/*.sh ; do
   . "$f"
done
END
