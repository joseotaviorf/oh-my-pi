#!/bin/sh
# Vendored from docker-library/docker@5b8430f91266d61c469b835aadb9ae2aa068bd27 (docker:29.6.2); Debian path adaptations only.
set -eu

for module; do
	if [ "${module#-}" = "$module" ]; then
		ip link show "$module" || true
		lsmod | grep "$module" || true
	fi
done

export PATH='/usr/sbin:/usr/bin:/sbin:/bin'
exec modprobe "$@"
