#!/usr/bin/env bash

### Vars
STEAM_DIR="${HOME}/.steam/steam"
STEAM_SHARE_DIR="${XDG_DATA_HOME}/Steam"

### Functions
function set_steam_userid {
  STEAM_UID_DIR="$(find "${STEAM_SHARE_DIR}/userdata" -maxdepth 1 -type d -name "[1-9]*" | head -n1)"
  STEAM_UID="${STEAM_UID_PATH##*/}"
  STEAM_SHORTCUTS="${STEAM_UID_DIR}/config/shortcuts.vdf"
}

function check_app_exist {
  local app_name="$1"
  if [ `grep -ac "$app_name" ${STEAM_SHORTCUTS}` -gt 0 ]; then
    return 1
  else
    return 0
  fi
}

function getCRC {
  echo -n "$1" | gzip -c | tail -c 8 | od -An -N 4 -tx4
}

function dec2hex {
  printf '%x\n' "$1"
}

function hex2dec {
  printf "%d\n" "0x${1#0x}"
}

function splitTags {
  mapfile -d "," -t -O "${#TAGARR[@]}" TAGARR < <(printf '%s' "$1")
  for i in "${!TAGARR[@]}"; do
          if grep -q "${TAGARR[$i]}" <<< "$(getActiveSteamCollections)"; then
                  printf '\x01%s\x00%s\x00' "$i" "${TAGARR[i]}"
          fi
  done
}

### Defaults
APP_HIDE=0
APP_DESKTOP_CONF=1
APP_OVERLAY=1
APP_VR=0

set_steam_userid

for arg in "$@"; do
  case $arg in
    --appname=*)
      APP_NAME="${arg#*=}"
      shift
    ;;
    --exepath=*)
      x="${arg#*=}"
      APP_EXEPATH="\"$x\""
      shift
    ;;
    --workdir=*)
      x="${arg#*=}";
      APP_WORKDIR="\"$x\""
      shift
    ;;
    --icon=*)
      APP_ICON="${arg#*=}"
      shift
    ;;
    --options=*)
      APP_OPTS="${arg#*=}"
      shift
    ;;
    --hide=*)
      APP_HIDE="${arg#*=}"
      shift
    ;;
    --allowdesktopconf=*)
      APP_DESKTOP_CONF="${arg#*=}"
      shift
    ;;
    --allowoverlay=*)
      APP_OVERLAY="${arg#*=}"
      shift
    ;;
    --openvr=*)
      APP_VR="${arg#*=}"
      shift
    ;;
    --tags=*)
      APP_TAGS="${i#*=}"
      shift
    ;;
    *)
    ;;
  esac
done

### Checks
if [ -z "${APP_EXEPATH}" ] && [ -z "${APP_NAME}" ]; then
  echo "error - no app name & path provided" >&2
  exit 0
fi

check_app_exist $APP_EXEPATH
is_app_exists=$?

if [ $is_app_exists -gt 0 ]; then
  echo "error - app ${APP_NAME} already exists" >&2
  exit 0
fi

### Main

# looks like the appid used here is randomly generated or at least not created from CRC
# (like the shortcutnames found in screenshots.vdf - see commented out lines)
# NOSTCRC="$(getCRC "${NOSTEXEPATH}${NOSTAPPNAME}")"
# NOSTSCNHEX="${NOSTCRC}02000000"
# echo "NOSTSCNHEX = ${NOSTSCNHEX}"
#
# Somehow other tools like Steam-Rom-Manager are able to generate correct AppIDs for Non-Steam Games
# Not sure how they do it even after trying to reproduce what they do in TypeScript locally
# Contributions would be very welcome on properly generating AppIDs for Non-Steam Games!

APP_ID_RND="$(printf "%03x%03x%02x\n" $((RANDOM%4096)) $((RANDOM%4096)) $((RANDOM%256)))" # APP ID NOSTAIDRHX
APP_ID_DEC="$(hex2dec "$APP_ID_RND")" # APP ID in DEC NOSTAID
APP_ID_HX="\x$(awk '{$1=$1}1' FPAT='.{2}' OFS="\\\x" <<< "$APP_ID_RND")" # ??? NOSTAIDHX

echo "=== Adding app ==="
echo "AppID: '${APP_ID_DEC}'"
echo "App Name: '${APP_NAME}'"
echo "Exe Path: '${APP_EXEPATH}'"
echo "Start Dir: '${APP_WORKDIR}'"
echo "Icon Path: '${APP_ICON}'"
echo "Launch options: '${APP_OPTS}'"
echo "Is Hidden: '${APP_HIDE}'"
echo "Allow Desktop Config: '${APP_DESKTOP_CONF}'"
echo "Allow Overlay: '${APP_OVERLAY}'"
echo "OpenVR: '${APP_VR}'"
echo "Tags: '${APP_TAGS}'"

if [ -f "$STEAM_SHORTCUTS" ]; then
  echo "The file '$STEAM_SHORTCUTS' already exists, creating a backup, then removing the 2 closing backslashes at the end"
  cp "$STEAM_SHORTCUTS" "${STEAM_SHORTCUTS}_nixdeck_bkp" 2>/dev/null
  truncate -s-2 "$STEAM_SHORTCUTS"
  OLDSET="$(grep -aPo '\x00[0-9]\x00\x02appid' "$STEAM_SHORTCUTS" | tail -n1 | tr -dc '0-9')"
  NEWSET=$((OLDSET + 1))
  echo "Last set in file has ID '$OLDSET', so continuing with '$OLDSET'"
else
  echo "Creating new $STEAM_SHORTCUTS"
  printf '\x00%s\x00' "shortcuts" > "$STEAM_SHORTCUTS"
  NEWSET=0
fi

echo "INFO" "Adding new set '$NEWSET'"

{
  printf '\x00%s\x00' "$NEWSET"
  printf '\x02%s\x00%b' "appid" "$APP_ID_HX"
  printf '\x01%s\x00%s\x00' "appname" "$APP_NAME"
  printf '\x01%s\x00%s\x00' "Exe" "$APP_EXEPATH"
  printf '\x01%s\x00%s\x00' "StartDir" "$APP_WORKDIR"

  if [ -n "$APP_ICON" ]; then
    printf '\x01%s\x00%s\x00' "icon" "$APP_ICON"
  else
    printf '\x01%s\x00\x00' "icon"
  fi

  printf '\x01%s\x00\x00' "ShortcutPath"

  if [ -n "$APP_OPTS" ]; then
    printf '\x01%s\x00%s\x00' "LaunchOptions" "$APP_OPTS"
  else
    printf '\x01%s\x00\x00' "LaunchOptions"
  fi

  if [ "$APP_HIDE" -eq 1 ]; then
    printf '\x02%s\x00\x01\x00\x00\x00' "IsHidden"
  else
    printf '\x02%s\x00\x00\x00\x00\x00' "IsHidden"
  fi

  if [ "$APP_DESKTOP_CONF" -eq 1 ]; then
    printf '\x02%s\x00\x01\x00\x00\x00' "AllowDesktopConfig"
  else
    printf '\x02%s\x00\x00\x00\x00\x00' "AllowDesktopConfig"
  fi

  if [ "$APP_OVERLAY" -eq 1 ]; then
    printf '\x02%s\x00\x01\x00\x00\x00' "AllowOverlay"
  else
    printf '\x02%s\x00\x00\x00\x00\x00' "AllowOverlay"
  fi

  if [ "$APP_VR" -eq 1 ]; then
    printf '\x02%s\x00\x01\x00\x00\x00' "openvr"
  else
    printf '\x02%s\x00\x00\x00\x00\x00' "openvr"
  fi

  printf '\x02%s\x00\x00\x00\x00\x00' "Devkit"
  printf '\x01%s\x00\x00' "DevkitGameID"

  printf '\x02%s\x00\x00\x00\x00\x00' "LastPlayTime"
  printf '\x00%s\x00' "tags"
  splitTags "$APP_TAGS"
  printf '\x08'
  printf '\x08'

  #file end:
  printf '\x08'
  printf '\x08'
} >> "$STEAM_SHORTCUTS"

echo "INFO" "Finished adding new app"

