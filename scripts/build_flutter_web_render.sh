#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Build do Flutter Web no RENDER (Static Site)
#
# Render não tem Flutter pré-instalado, então nós baixamos o
# SDK do Flutter stable durante o build, adicionamos ao PATH
# e rodamos `flutter build web --release`.
#
# Publicar em: frontend_flutter/build/web
# ============================================================

FLUTTER_VERSION="3.27.1-stable"
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

echo ">>> 1/5 Setup pastas de trabalho"
mkdir -p /tmp/flutter-sdk
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
FRONT_DIR="${PROJECT_ROOT}/frontend_flutter"
echo "    Project root : ${PROJECT_ROOT}"
echo "    Frontend dir : ${FRONT_DIR}"

echo ">>> 2/5 Baixando Flutter SDK (${FLUTTER_VERSION})"
cd /tmp/flutter-sdk
if [ ! -f "${FLUTTER_ARCHIVE}" ]; then
  curl -fsSL -o "${FLUTTER_ARCHIVE}" "${FLUTTER_URL}"
else
  echo "    (cache local encontrado, pulando download)"
fi
echo "    Extraindo tarball..."
tar -xf "${FLUTTER_ARCHIVE}"
export PATH="/tmp/flutter-sdk/flutter/bin:/tmp/flutter-sdk/flutter/bin/cache/dart-sdk/bin:${PATH}"
flutter --version --machine | head -n 5

echo ">>> 3/5 flutter pub get (frontend_flutter)"
cd "${FRONT_DIR}"
flutter pub get

echo ">>> 4/5 flutter build web --release"
flutter build web --release

echo ">>> 5/5 Build concluido. Tamanho de build/web:"
du -sh "${FRONT_DIR}/build/web"
find "${FRONT_DIR}/build/web" -type f | wc -l
echo ">>> OK. Publicar em: frontend_flutter/build/web"
