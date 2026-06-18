#!/usr/bin/env bash
#
# bootstrap.sh — install the build toolchain for the "ArtNet PoC" Flutter app.
#
# What it installs (best-effort, idempotent, safe to re-run):
#   - Flutter SDK + Dart            (via Homebrew cask)        [required]
#   - CocoaPods                     (via Homebrew)             [required for iOS]
#   - Xcode command-line setup      (license + first launch)  [iOS device/sim builds]
#   - Android command-line SDK      (via Homebrew cask)        [optional, Android builds]
#
# This script ONLY installs tooling. It does NOT scaffold or build the app.
# After it finishes, open a NEW terminal, confirm `flutter --version` works, then
# tell the assistant to continue with Phase 1 (scaffold + app code).
#
# Usage:
#   bash scripts/bootstrap.sh              # install everything (incl. Android)
#   SKIP_ANDROID=1 bash scripts/bootstrap.sh   # skip the Android SDK section
#   SKIP_XCODE=1   bash scripts/bootstrap.sh   # skip Xcode license/first-launch
#
set -u

# ----- pretty output -------------------------------------------------------
BOLD="$(tput bold 2>/dev/null || true)"; RESET="$(tput sgr0 2>/dev/null || true)"
info()  { printf '%s\n' "${BOLD}==>${RESET} $*"; }
ok()    { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '    \033[33m! %s\033[0m\n' "$*"; }
err()   { printf '    \033[31m✗ %s\033[0m\n' "$*"; }
have()  { command -v "$1" >/dev/null 2>&1; }

FAILED=0

# ----- 0. sanity: macOS + Homebrew ----------------------------------------
info "Checking prerequisites (macOS + Homebrew)"
if [ "$(uname -s)" != "Darwin" ]; then
  err "This bootstrap script targets macOS. Detected: $(uname -s)."
  err "Install Flutter manually: https://docs.flutter.dev/get-started/install"
  exit 1
fi

if ! have brew; then
  err "Homebrew not found. Install it first:"
  err '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
BREW_PREFIX="$(brew --prefix)"
ok "Homebrew at ${BREW_PREFIX}"

# ----- 1. Flutter (required) ----------------------------------------------
info "Installing Flutter SDK + Dart"
if have flutter; then
  ok "flutter already installed: $(flutter --version 2>/dev/null | head -1)"
else
  if brew install --cask flutter; then
    ok "Flutter installed"
  else
    err "Failed to install Flutter via Homebrew cask"
    FAILED=1
  fi
fi

# ----- 2. CocoaPods (required for iOS) -------------------------------------
info "Installing CocoaPods (needed for iOS plugin builds)"
if have pod; then
  ok "CocoaPods already installed: $(pod --version 2>/dev/null)"
else
  if brew install cocoapods; then
    ok "CocoaPods installed"
  else
    warn "Failed to install CocoaPods via brew. Alternative: 'sudo gem install cocoapods'"
    FAILED=1
  fi
fi

# ----- 3. Xcode command-line setup (iOS) ----------------------------------
if [ "${SKIP_XCODE:-0}" = "1" ]; then
  info "Skipping Xcode setup (SKIP_XCODE=1)"
elif have xcodebuild; then
  info "Configuring Xcode (license + first launch — may prompt for your password)"
  if ! xcodebuild -version >/dev/null 2>&1; then
    warn "Xcode license not accepted yet; running 'sudo xcodebuild -license accept'"
    sudo xcodebuild -license accept || warn "Could not accept Xcode license automatically"
  fi
  # Installs additional required components (simulators runtimes, etc.)
  sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 && ok "Xcode first-launch components ready" \
    || warn "xcodebuild -runFirstLaunch reported an issue (often harmless)"
else
  warn "xcodebuild not found. Install Xcode from the App Store for iOS builds."
fi

# ----- 4. Android SDK (optional) ------------------------------------------
if [ "${SKIP_ANDROID:-0}" = "1" ]; then
  info "Skipping Android SDK (SKIP_ANDROID=1)"
else
  info "Installing Android command-line SDK (optional — needed only for Android builds)"
  if ! have sdkmanager && ! brew list --cask android-commandline-tools >/dev/null 2>&1; then
    brew install --cask android-commandline-tools \
      && ok "android-commandline-tools installed" \
      || warn "Could not install android-commandline-tools (you can use Android Studio instead)"
  else
    ok "Android command-line tools already present"
  fi

  # Pick a sane ANDROID_HOME. The Homebrew cask lays out a valid SDK root here.
  ANDROID_HOME_GUESS="${ANDROID_HOME:-${BREW_PREFIX}/share/android-commandline-tools}"
  if [ -d "$ANDROID_HOME_GUESS" ]; then
    export ANDROID_HOME="$ANDROID_HOME_GUESS"
    export ANDROID_SDK_ROOT="$ANDROID_HOME_GUESS"
    ok "ANDROID_HOME=$ANDROID_HOME"

    if have sdkmanager; then
      info "Installing platform-tools + Android 35 platform + build-tools (accepting licenses)"
      yes | sdkmanager --licenses >/dev/null 2>&1 || true
      sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" \
        && ok "Android SDK components installed" \
        || warn "sdkmanager could not install all components; check 'flutter doctor -v'"
    else
      warn "sdkmanager not on PATH; skipping SDK component install"
    fi

    # Point Flutter at this SDK and persist env vars to ~/.zshrc (guarded block).
    if have flutter; then
      flutter config --android-sdk "$ANDROID_HOME" >/dev/null 2>&1 || true
      yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
    fi

    ZSHRC="$HOME/.zshrc"
    MARKER="# >>> artnet-poc android env >>>"
    if ! grep -qF "$MARKER" "$ZSHRC" 2>/dev/null; then
      {
        printf '\n%s\n' "$MARKER"
        printf 'export ANDROID_HOME="%s"\n' "$ANDROID_HOME"
        printf 'export ANDROID_SDK_ROOT="%s"\n' "$ANDROID_HOME"
        printf 'export PATH="$ANDROID_HOME/platform-tools:$PATH"\n'
        printf '%s\n' "# <<< artnet-poc android env <<<"
      } >> "$ZSHRC"
      ok "Appended ANDROID_HOME exports to $ZSHRC (open a new shell to pick them up)"
    else
      ok "ANDROID env block already present in $ZSHRC"
    fi
  else
    warn "Could not locate an Android SDK root. For Android builds, install Android Studio:"
    warn "  brew install --cask android-studio   (then open it once to finish SDK setup)"
  fi
fi

# ----- 5. flutter doctor ---------------------------------------------------
if have flutter; then
  info "Running 'flutter doctor -v' (review any ✗ items below)"
  flutter doctor -v || true
fi

# ----- 6. next steps -------------------------------------------------------
echo
info "Bootstrap complete."
if [ "$FAILED" = "1" ]; then
  warn "One or more REQUIRED installs failed — re-run after fixing, or install manually."
fi
cat <<'NEXT'

Next steps:
  1. Open a NEW terminal window (so PATH / env changes take effect).
  2. Confirm the toolchain:   flutter --version
                              flutter doctor
  3. If 'flutter --version' works, tell the assistant:
        "Flutter is installed — continue with Phase 1."
     It will then scaffold the project and write the app code, running
     'flutter analyze' and 'flutter test' as it goes.

Notes:
  - iOS local-network features (Art-Net broadcast, Bonjour/mDNS) must be tested on a
    REAL iPhone/iPad, not the Simulator.
  - Android multicast/broadcast reception needs a real device on real Wi-Fi too.
NEXT
