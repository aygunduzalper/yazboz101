#!/bin/bash
# iPhone simülatöründe Yazboz 101 denemesi (GitHub Actions'taki bulut Mac'te çalışır).
# Kullanım: bash test/ios.sh <çıktı klasörü>
# Yaptıkları: test (Debug) sürümünü derler, büyük ve (varsa) küçük ekranlı bir iPhone'da
# ilk açılış + senaryo, kapat-aç, sil-yükle-aç ve gece modunu dener; ekran görüntülerini toplar.
set -uo pipefail
OUT="${1:-sonuc}"
BID=com.aygunduz.yazboz101
mkdir -p "$OUT"

echo "::group::Derleme"
if ! xcodebuild -project ios/Yazboz101.xcodeproj -scheme Yazboz101 -configuration Debug \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/sim \
     CODE_SIGNING_ALLOWED=NO build > "$OUT/derleme.log" 2>&1; then
  tail -60 "$OUT/derleme.log"
  mkdir -p "$OUT/ios-derleme"
  grep -E "error:|BUILD FAILED" "$OUT/derleme.log" | head -40 > "$OUT/ios-derleme/hatalar.txt"
  python3 -c 'import json,sys; json.dump({"platform":"ios","cihaz":"derleme","sorunlar":["iOS derlemesi başarısız"],"konsol":open(sys.argv[1]).read().splitlines()}, open(sys.argv[2],"w"), ensure_ascii=False)' "$OUT/ios-derleme/hatalar.txt" "$OUT/ios-derleme/sonuc.json"
  rm -f "$OUT/derleme.log"
  exit 1
fi
rm -f "$OUT/derleme.log"
echo "::endgroup::"
APP=$(ls -d build/sim/Build/Products/Debug-iphonesimulator/*.app | head -1)
echo "Uygulama: $APP"

# Simülatör seç: en yeni iOS sürümündeki, adı tam olarak eşleşen iPhone
pick() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
pat = re.compile(sys.argv[1])
c = [(k, x) for k, v in d.items() if "iOS" in k for x in v if pat.fullmatch(x["name"])]
c.sort(key=lambda t: [int(n) for n in re.findall(r"\d+", t[0])])
print(c[-1][1]["udid"] + "|" + c[-1][1]["name"] + "|" + c[-1][0].split(".")[-1] if c else "")' "$1"
}

shot() { xcrun simctl io "$1" screenshot "$2" > /dev/null 2>&1 || true; }

run_device() {
  local UDID="$1" TAG="$2" NAME="$3" RT="$4"
  local D="$OUT/$TAG"
  mkdir -p "$D"
  echo "::group::$NAME ($RT)"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl install "$UDID" "$APP"

  # 1) İlk açılış + senaryo
  SIMCTL_CHILD_YAZBOZ_TEST="$(cat test/senaryo.js)" xcrun simctl launch "$UDID" "$BID" > /dev/null
  sleep 2
  shot "$UDID" "$D/a-ilk-acilis-2sn.png"
  local DATA
  DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data)
  for _ in $(seq 1 150); do [ -f "$DATA/Documents/test/sonuc.json" ] && break; sleep 1; done
  shot "$UDID" "$D/a-senaryo-sonu.png"
  cp "$DATA"/Documents/test/* "$D/" 2>/dev/null || true
  [ -f "$D/sonuc.json" ] && mv "$D/sonuc.json" "$D/senaryo.json"

  # 2) Kapat-aç
  xcrun simctl terminate "$UDID" "$BID" 2> /dev/null; sleep 1
  xcrun simctl launch "$UDID" "$BID" > /dev/null; sleep 4
  shot "$UDID" "$D/b-kapat-ac.png"

  # 3) Sil-yükle-aç
  xcrun simctl uninstall "$UDID" "$BID"
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$BID" > /dev/null
  sleep 2; shot "$UDID" "$D/c-yeniden-kurulum-2sn.png"
  sleep 6; shot "$UDID" "$D/c-yeniden-kurulum-8sn.png"

  # 4) Gece modu
  xcrun simctl ui "$UDID" appearance dark
  xcrun simctl terminate "$UDID" "$BID" 2> /dev/null; sleep 1
  xcrun simctl launch "$UDID" "$BID" > /dev/null; sleep 4
  shot "$UDID" "$D/d-gece-modu.png"
  xcrun simctl ui "$UDID" appearance light

  xcrun simctl spawn "$UDID" log show --last 15m --style compact \
    --predicate 'eventMessage CONTAINS "YAZBOZ" OR (process == "Yazboz101" AND messageType == fault)' > "$D/log.txt" 2>&1 || true
  python3 - "$D" "$NAME" "$RT" <<'PY'
import json, os, sys
d, name, rt = sys.argv[1:4]
S = {"platform": "ios", "cihaz": f"{name} · iOS {rt.replace('iOS-', '').replace('-', '.')}", "senaryo": None, "konsol": [], "sorunlar": []}
p = os.path.join(d, "senaryo.json")
if os.path.exists(p):
    try: S["senaryo"] = json.load(open(p))
    except Exception as e: S["senaryo"] = {"ok": False, "hata": "okunamadı: " + str(e)}
else:
    S["sorunlar"].append("Senaryo sonucu gelmedi (uygulama açılmamış ya da takılmış olabilir)")
if S["senaryo"] and not S["senaryo"].get("ok"): S["sorunlar"].append("Senaryoda başarısız adım var")
k = os.path.join(d, "konsol.txt")
if os.path.exists(k): S["konsol"] = [l for l in open(k, encoding="utf-8", errors="replace").read().splitlines() if l.strip()][:200]
json.dump(S, open(os.path.join(d, "sonuc.json"), "w"), ensure_ascii=False, indent=2)
print("Sorunlar:", S["sorunlar"] or "yok")
PY
  xcrun simctl shutdown "$UDID" 2> /dev/null || true
  echo "::endgroup::"
}

BIG=$(pick 'iPhone \d+')
SMALL=$(pick 'iPhone SE \(3rd generation\)')
[ -z "$BIG" ] && BIG=$(pick 'iPhone.*')
IFS='|' read -r U N R <<< "$BIG"
[ -n "$U" ] && run_device "$U" "ios-buyuk" "$N" "$R"
if [ -n "$SMALL" ]; then
  IFS='|' read -r U N R <<< "$SMALL"
  run_device "$U" "ios-kucuk" "$N" "$R"
fi
exit 0
