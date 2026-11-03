#!/bin/bash
# run.sh [--update] [name ...] -- play each game in cases.txt on this Mac and check where it got to.
#
# Each game runs in its harness for a while, a screenshot is taken, and the run passes if the game did not crash, the
# screenshot is not black, and it looks like ref/<name>.png. --update makes the screenshots the new references (look at
# them first). Output goes to $HUSK_REGRESS_OUT (default /tmp/husk-regress): the screenshots, each game's log and a
# summary. Takes a few minutes; Minecraft is most of it.
#
# HUSK_REGRESS_JITLESS=1: Husk 3.2's JIT-less mode. Each game's libraries (and the Java runtime's) are converted into dylibs first
# (elf2macho-test --prepare, cached in $CACHE/aot), and the game runs from them with no executable memory at all (TL_NO_XMEM=1).
# HUSK_REGRESS_NO_ALIAS=1 also leaves out the step iOS refuses (sharing data pages with the code view), as on a phone.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
OUT="${HUSK_REGRESS_OUT:-/tmp/husk-regress}"; CACHE="${HUSK_REGRESS_CACHE:-$HOME/Library/Caches/husk-regress}"
UPDATE=0; [ "${1:-}" = "--update" ] && { UPDATE=1; shift; }
ONLY=" $* "
mkdir -p "$OUT" "$CACHE"

expand() { eval echo "$1"; }

BUILT=" "
fails=0; passes=0; skips=0
printf "%-15s %-8s %s\n" "game" "result" "detail" | tee "$OUT/summary.txt"
while IFS='|' read -r name harness apk secs size env expect; do
    name=$(echo $name); [ -z "$name" ] || [ "${name:0:1}" = "#" ] && continue
    [ "$ONLY" != "  " ] && [[ "$ONLY" != *" $name "* ]] && continue
    harness=$(echo $harness); apk=$(echo $apk); secs=$(echo $secs); size=$(echo $size); env=$(echo $env)
    expect="$(echo "${expect:-}" | sed 's/^ *//; s/ *$//')"

    if [[ "$apk" == fdroid:* ]]; then
        id=${apk#fdroid:}; apk="$CACHE/$id.apk"
        [ -s "$apk" ] || curl -sfL -o "$apk" "https://f-droid.org/repo/$id.apk" || rm -f "$apk"
    else
        apk=$(expand "$apk")
    fi
    if [ ! -f "$apk" ]; then
        printf "%-15s %-8s %s\n" "$name" "skipped" "no APK ($apk)" | tee -a "$OUT/summary.txt"; skips=$((skips + 1)); continue
    fi

    bin="$OUT/$harness"
    if [[ "$BUILT" != *" $harness "* ]]; then
        if ! bash "$HERE/build.sh" "tools/$harness.c" "$bin" > "$OUT/build-$harness.log" 2>&1; then
            printf "%-15s %-8s %s\n" "$name" "FAILED" "the $harness harness did not build (build-$harness.log)" | tee -a "$OUT/summary.txt"
            fails=$((fails + 1)); continue
        fi
        BUILT="$BUILT$harness "
    fi

    jitless=""
    if [ "${HUSK_REGRESS_JITLESS:-0}" = 1 ]; then
        if [[ "$BUILT" != *" elf2macho-test "* ]]; then
            bash "$HERE/build.sh" tools/elf2macho-test.c "$OUT/elf2macho-test" > "$OUT/build-elf2macho-test.log" 2>&1 || { echo "elf2macho-test did not build"; exit 1; }
            BUILT="${BUILT}elf2macho-test "
        fi
        splits=$(echo " $(expand "$env") " | sed -n 's/.* TL_SPLITS=\([^ ]*\) .*/\1/p' | tr ':' ' ')
        if ! "$OUT/elf2macho-test" --prepare "$CACHE/aot" "$apk" $splits $(find "$R/build/java-runtime" -name '*.so' 2>/dev/null) > "$OUT/$name.prepare.log" 2>&1; then
            printf "%-15s %-8s %s\n" "$name" "FAILED" "preparing dylibs failed ($name.prepare.log)" | tee -a "$OUT/summary.txt"
            fails=$((fails + 1)); continue
        fi
        jitless="TL_NO_XMEM=1 TL_AOT_DIR=$CACHE/aot"
        [ "${HUSK_REGRESS_NO_ALIAS:-0}" = 1 ] && jitless="$jitless TL_AOT_NO_ALIAS=1"
        # JIT-less runs reach their first screen more slowly (dylibs mapped from disk, nothing warmed up); give them more time
        secs=$((secs * 3 / 2 + 10))
    fi
    shot="$OUT/$name.png"; log="$OUT/$name.log"; ctl="$OUT/$name.ctl"; rm -f "$shot"
    data=$(mktemp -d /tmp/husk-regress-data.XXXXXX)
    # one run of the game: the harness is left running for secs, which takes a screenshot (and its log) at the end
    play() {
        printf "wait %d\nshot %s\nquit\n" $((secs * 1000)) "$shot" > "$ctl"
        pkill -9 -x "$harness" 2>/dev/null
        ( cd "$OUT" && env TL_AUDIO_MUTE=1 TL_JNI_TRACE=0 TL_VERBOSE=0 TL_CTL="$ctl" TL_DATA="$data" $(expand "$env") $jitless \
            timeout $((secs + 60)) "$bin" "$apk" $((secs + 30)) $size ) > "$log" 2>&1
        rc=$?
    }
    play
    retried=""
    # The Java harness's compositor and the game's own EGL window race, so a run occasionally ends on a black frame even though
    # the game is on screen (see 3.2-progress.md): one more run decides it.
    if [ $UPDATE = 0 ] && [ -s "$shot" ] && ! grep -q "=== CRASH\|\*\*\* FATAL" "$log" \
       && [ "$(python3 -I "$HERE/compare.py" "$shot" "$HERE/ref/$name.png")" = black ]; then
        mv "$log" "$OUT/$name.first.log"; play; retried=" (after a second run)"
    fi
    rm -rf "$data" /tmp/husk-frames-* /tmp/husk-mframes-* /tmp/husk-unity-* /tmp/husk-mc-* 2>/dev/null

    if grep -q "=== CRASH\|\*\*\* FATAL" "$log"; then
        result=FAILED; detail="crashed: $(grep -m1 '=== CRASH\|\*\*\* FATAL' "$log")$retried"
    elif [ -n "$expect" ] && ! grep -qF "$expect" "$log"; then
        result=FAILED; detail="the log never says \"$expect\"$retried"
    elif [ ! -s "$shot" ]; then
        result=FAILED; detail="no screenshot (exit $rc; see $name.log)$retried"
    elif [ $UPDATE = 1 ]; then
        sips -Z 400 "$shot" --out "$HERE/ref/$name.png" >/dev/null; result=updated; detail="new reference"
    else
        c=$(python3 -I "$HERE/compare.py" "$shot" "$HERE/ref/$name.png"); 
        case "$c" in ok*) result=passed; detail="picture ${c#ok }$retried";; *) result=FAILED; detail="picture: $c$retried";; esac
    fi
    [ "$result" = FAILED ] && fails=$((fails + 1)) || passes=$((passes + 1))
    printf "%-15s %-8s %s\n" "$name" "$result" "$detail" | tee -a "$OUT/summary.txt"
done < "$HERE/cases.txt"

echo "$passes passed, $fails failed, $skips skipped -- $OUT" | tee -a "$OUT/summary.txt"
[ $fails = 0 ]
