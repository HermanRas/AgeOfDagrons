#!/usr/bin/env bash
# Restore 0 A.D. art sources that a bake rewrote in place.
#
# WHY THIS IS NEEDED. The Pyrogenesis importer rewrites every .dae it loads,
# and isobake undoes that via preserve_sources() -- but the restore is the one
# piece of state SHARED between parallel bake slots, so two recipes loading the
# same mesh at once can clobber each other's restore. Cavalry and infantry all
# pull horse_celtic.dae and m_tunic_short.dae, so a wide batch reliably leaves
# a few dozen meshes dirty. A killed batch leaves them dirty too.
#
# WHY IT USES git-lfs AND NOT `git checkout`. HEAD stores LFS POINTERS, not
# content: a 136-byte stub where a 226 KB mesh belongs. `git checkout -- <path>`
# on Windows, where git-lfs is not installed, would happily replace real
# geometry with the stub and destroy the art. git-lfs lives in WSL on this
# machine, so run this from there:
#
#     wsl -e bash -c "tr -d '\r' < tools/restore_art_sources.sh | bash"
#
# The pointer's `oid` IS the sha256 of the pristine content, so comparing it
# against sha256sum on disk is an exact test, and the pristine bytes are already
# in .git/lfs/objects -- no network needed. Restoring is a copy, which
# deliberately leaves git's index alone (it carries ~30k staged deletions from
# the LFS setup; touching it is a separate problem and not this script's job).
#
# Pass --apply to write. Default is a dry run.
set -u

REPO=/mnt/c/Users/herman.ras/Downloads/AOD_game/art_source/0ad
ART=binaries/data/mods/public/art
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

cd "$REPO" || { echo "cannot cd to $REPO"; exit 1; }

clean=0; dirty=0; fixed=0; nocache=0; failed=0

while IFS= read -r f; do
  ptr=$(git show "HEAD:$f" 2>/dev/null) || continue
  case "$ptr" in
    version*git-lfs*) ;;
    *) continue ;;                      # not LFS-managed; nothing to compare to
  esac
  oid=$(printf '%s' "$ptr" | sed -n 's/^oid sha256://p')
  [ -n "$oid" ] || continue

  disk=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
  if [ "$oid" = "$disk" ]; then clean=$((clean+1)); continue; fi

  dirty=$((dirty+1))
  obj=".git/lfs/objects/${oid:0:2}/${oid:2:2}/$oid"
  if [ ! -f "$obj" ]; then
    echo "  NO CACHED OBJECT  $f"
    nocache=$((nocache+1))
    continue
  fi
  # Guard against a corrupt cache: the object must hash to its own name.
  if [ "$(sha256sum "$obj" | cut -d' ' -f1)" != "$oid" ]; then
    echo "  CACHE CORRUPT     $f"
    failed=$((failed+1))
    continue
  fi

  if [ "$APPLY" = "1" ]; then
    if cp -- "$obj" "$f" && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$oid" ]; then
      fixed=$((fixed+1))
    else
      echo "  RESTORE FAILED    $f"
      failed=$((failed+1))
    fi
  else
    echo "  would restore     $f"
  fi
done < <(find "$ART" -name '*.dae' -type f 2>/dev/null)

echo
echo "already pristine : $clean"
echo "modified         : $dirty"
if [ "$APPLY" = "1" ]; then
  echo "restored         : $fixed"
else
  echo "(dry run -- pass --apply to restore)"
fi
[ "$nocache" -gt 0 ] && echo "no cached object : $nocache  (needs: git lfs pull)"
[ "$failed"  -gt 0 ] && echo "FAILED           : $failed"
exit 0
