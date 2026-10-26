#!/usr/bin/env bash
# Message catalogue for menu.sh. Source after lib.sh, don't execute.
#   i18n_load cs     load English, then overlay scripts/locale/cs.sh (missing strings stay English)
#   t KEY [ARGS…]    print the message for KEY (a printf format), or KEY itself if it's unknown
# Add a language: scripts/locale/<code>.sh, the code in LANGS and valid_lang (lib.sh), menu.lang.<code>.

LOCALE_DIR="$REPO_DIR/scripts/locale"
LANGS=(en cs)
declare -gA MSG=()
I18N_LANG=en

# MENU_LANG from .env if valid, else the system locale.
i18n_detect() {
  if [[ -n ${MENU_LANG:-} ]] && valid_lang "$MENU_LANG"; then
    echo "$MENU_LANG"
    return 0
  fi
  case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
    cs*) echo cs ;;
    *) echo en ;;
  esac
}

i18n_load() {
  local lang="$1"
  valid_lang "$lang" || lang=en
  MSG=()
  # shellcheck source=locale/en.sh
  . "$LOCALE_DIR/en.sh"
  if [[ $lang != en ]]; then
    # shellcheck disable=SC1090
    . "$LOCALE_DIR/$lang.sh"
  fi
  I18N_LANG="$lang"
}

t() {
  local key="$1"
  shift
  # shellcheck disable=SC2059 # the catalogue entry is the format
  printf -- "${MSG[$key]:-$key}" "$@"
}
