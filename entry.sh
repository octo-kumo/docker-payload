#!/bin/sh
# Simple in-docker payload for testing / security research
set -eu

echo "=== Environment variables ==="
env || true
echo

echo "=== Basic info ==="
echo "Date: $(date -u)"
echo "Hostname: $(cat /proc/sys/kernel/hostname 2>/dev/null || hostname)"
echo "UID: $(id -u 2>/dev/null || echo unknown)  GID: $(id -g 2>/dev/null || echo unknown)"
echo

# Print mount table
echo "=== Mounts (/proc/mounts) ==="
if [ -r /proc/mounts ]; then
  awk '{printf "%-40s <- %-30s (%s)\n",$2,$1,$3}' /proc/mounts
else
  echo "/proc/mounts not readable"
fi
echo

caphex=$(awk '/CapEff/ {print $2}' /proc/self/status 2>/dev/null || echo 0)
capdec=$(printf "%d" "0x${caphex}" 2>/dev/null || echo 0)

has_cap() {
  bit="$1"   # bit number (0-based)
  mask=$((1 << bit))
  if [ $((capdec & mask)) -ne 0 ]; then
    echo "yes"
  else
    echo "no"
  fi
}

echo "=== Capability / privilege checks ==="
echo "CapEff (hex): ${caphex}"
# Common capability bit numbers (Linux): CAP_CHOWN=0, CAP_NET_ADMIN=12, CAP_SYS_ADMIN=21
printf "CAP_SYS_ADMIN (bit 21) present? %s\n" "$(has_cap 21)"
printf "CAP_NET_ADMIN (bit 12) present? %s\n" "$(has_cap 12)"
printf "Running as root? %s\n" "$( [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && echo yes || echo no )"

# Another rough check: does /dev/kmsg exist and is writable (often only in privileged containers)
if [ -w /dev/kmsg ] 2>/dev/null; then
  echo "/dev/kmsg writable: yes (may indicate host-level access / privileged)"
else
  echo "/dev/kmsg writable: no"
fi

echo

# Volumes: list mounts that look like bind-volumes (heuristic)
echo "=== Heuristic: likely bind/volume mounts (subset of mounts) ==="
if [ -r /proc/self/mounts ]; then
  awk '
  BEGIN { print "mountpoint <- source (fstype)" }
  {
    src=$1; mnt=$2; fstype=$3;
    # heuristics: if src starts with "/" (host path, device), or src contains "overlay" or "docker"
    if (src ~ "^/" || src ~ /overlay/ || src ~ /docker/ || src ~ /volumes/) {
      printf "%-30s <- %-40s (%s)\n", mnt, src, fstype
    }
  }' /proc/self/mounts
else
  echo "cannot read /proc/self/mounts"
fi
echo

echo "=== End debug info ==="
# Keep container alive if user passed KEEP_ALIVE=1 (useful for interactive debug)
if [ "${KEEP_ALIVE:-}" = "1" ]; then
  echo "KEEP_ALIVE set — sleeping forever. Attach with: docker exec -it <id> sh"
  while true; do sleep 86400; done
fi

# If env.CODE is set, execute it as shell code
if [ -n "${CODE:-}" ]; then
  echo "Executing code from env.CODE:"
  sh -c "$CODE"
  echo "=== End of CODE execution ==="
fi

# allow the container to exit normally
exit 0