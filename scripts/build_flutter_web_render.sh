#!/usr/bin/env bash
# ============================================================================
# Build do Flutter Web no RENDER (Static Site)
#
# Versão ROBUSTA (V2):
#   · Usa versão do Flutter TESTADA e PRESENTE no storage.googleapis.com
#   · Logs VERBOSOS (set -x) para facilitar debug no Dashboard do Render
#   · Sempre habilita plataforma WEB (evita erros de toolchain não ativado)
#   · Roda flutter doctor -v (mostra se SDK tá 100%)
#   · flutter clean ANTES de cada build (não usa cache de build antigo)
#   · Timeout cURL e retry (evita falha de rede intermitente no Render)
#
# Publica em: ./frontend_flutter/build/web
# ============================================================================
set -euo pipefail
set -x  # ⚠️ LOG CADA LINHA (deixa o build log do Render legível)

# ----------------------------------------------------------------------------
# ⚙️ Versão do Flutter (GARANTA que tar.xz EXISTA em storage.googleapis.com):
#   Acesse: https://docs.flutter.dev/release/archive?tab=linux
#   3.24.0 stable = lançada Ago/2024, 100% compatível com Render Linux x86_64.
#   (3.27.1 era muito nova / não publicada no archive Linux no momento do deploy)
# ----------------------------------------------------------------------------
FLUTTER_VERSION="3.24.0-stable"
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

echo ""
echo "======================================================"
echo " STEP 1/6 - Setup pastas de trabalho"
echo "======================================================"
mkdir -p /tmp/flutter-sdk
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
FRONT_DIR="${PROJECT_ROOT}/frontend_flutter"
echo "    Project root : ${PROJECT_ROOT}"
echo "    Frontend dir : ${FRONT_DIR}"
echo "    Flutter ver  : ${FLUTTER_VERSION}"
echo "    URL archive  : ${FLUTTER_URL}"

echo ""
echo "======================================================"
echo " STEP 2/6 - Baixar / extrair Flutter SDK"
echo "======================================================"
cd /tmp/flutter-sdk
if [ ! -f "${FLUTTER_ARCHIVE}" ]; then
  curl -fsSL --retry 3 --retry-delay 2 --max-time 300 \
    -o "${FLUTTER_ARCHIVE}" \
    "${FLUTTER_URL}"
  echo "    (download OK - $(du -h "${FLUTTER_ARCHIVE}" | cut -f1))"
else
  echo "    (cache local encontrado - pulando download)"
fi

echo "    Extraindo tarball (isso demora ~30-60s) ..."
tar -xf "${FLUTTER_ARCHIVE}"

export PATH="/tmp/flutter-sdk/flutter/bin:/tmp/flutter-sdk/flutter/bin/cache/dart-sdk/bin:${PATH}"
export PUB_CACHE="/tmp/pub-cache"
mkdir -p "${PUB_CACHE}"
export FLUTTER_ROOT="/tmp/flutter-sdk/flutter"

echo "    Dart version  : $(dart --version 2>&1 || true)"
echo "    Flutter bin   : $(which flutter)"

echo ""
echo "======================================================"
echo " STEP 3/6 - flutter doctor + habilita WEB"
echo "======================================================"
# Habilita plataforma WEB explicitamente (evita pegadinha de SDK "não inicializado")
flutter config --enable-web --no-enable-linux-desktop --no-enable-windows-desktop --no-enable-macos-desktop 2>&1 | tail -n 5 || true
# Doctor mostra se SDK tá funcional (faltam ferramentas? loga e segue)
flutter doctor -v 2>&1 | tail -n 30 || true

echo ""
echo "======================================================"
echo " STEP 4/6 - flutter clean + pub get (reseta build cache)"
echo "======================================================"
cd "${FRONT_DIR}"
flutter clean 2>&1 | tail -n 10 || true
echo "    Baixando dependências (flutter pub get)..."
flutter pub get 2>&1 | tail -n 15

echo ""
echo "======================================================"
echo " STEP 5/6 - BUILD WEB RELEASE (demora ~1-2 min)"
echo "======================================================"
# --base-href=/ : site servido na raiz do domínio (tiago-frontend.onrender.com/)
# --release: tree-shake, obfuscação, sem asserts
flutter build web \
  --release \
  --base-href=/ \
  2>&1 | tail -n 40

echo ""
echo "======================================================"
echo " STEP 6/6 - Validação pós-build"
echo "======================================================"
BUILD_DIR="${FRONT_DIR}/build/web"
if [ -f "${BUILD_DIR}/index.html" ] && [ -f "${BUILD_DIR}/main.dart.js" ]; then
  echo "✅ Build CONCLUÍDO!"
  echo "   index.html      : $(du -h "${BUILD_DIR}/index.html" | cut -f1)"
  echo "   main.dart.js    : $(du -h "${BUILD_DIR}/main.dart.js" | cut -f1)"
  echo "   Tamanho total   : $(du -sh "${BUILD_DIR}" | cut -f1)"
  echo "   Arquivos total  : $(find "${BUILD_DIR}" -type f | wc -l)"
  echo ""
  echo "   Publicar em (publishDir do Render): frontend_flutter/build/web"
else
  echo "❌ Build FALHOU. Arquivos críticos não existem em ${BUILD_DIR}"
  ls -la "${BUILD_DIR}" 2>&1 || true
  exit 64
fi
