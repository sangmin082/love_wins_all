#!/usr/bin/env bash
# iOS TestFlight 공통 GitHub Secrets를 저장소에 한 번에 등록하는 스크립트.
#
# 값을 로컬 env 파일에 한 번만 적어 두면, 새 앱 저장소를 만들 때마다
# 이 스크립트 한 줄로 Secrets 7개가 전부 등록된다:
#
#   ./scripts/setup-secrets.sh sangmin082/새앱저장소
#
# 준비 (최초 1회):
#   1. GitHub CLI 설치 + 로그인:  brew install gh && gh auth login
#   2. env 파일 작성:  cp scripts/ios-secrets.env.example ~/.config/ios-secrets.env
#      → 파일을 열어 실제 값 입력 (chmod 600 권장, git에 절대 커밋 금지)
#
# env 파일 위치를 바꾸려면 두 번째 인자로 경로를 넘긴다.
set -euo pipefail

REPO="${1:?사용법: setup-secrets.sh <owner/repo> [env파일 경로]}"
ENV_FILE="${2:-$HOME/.config/ios-secrets.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ env 파일이 없습니다: $ENV_FILE"
  echo "   cp scripts/ios-secrets.env.example ~/.config/ios-secrets.env 후 값을 채워주세요."
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

SECRETS=(
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_KEY
  APPLE_TEAM_ID
  MATCH_GIT_URL
  MATCH_GIT_BASIC_AUTHORIZATION
  MATCH_PASSWORD
)

for name in "${SECRETS[@]}"; do
  if [ -z "${!name:-}" ]; then
    echo "❌ env 파일에 값이 없습니다: $name"
    exit 1
  fi
done

echo "→ $REPO 에 Secrets ${#SECRETS[@]}개 등록 중…"
for name in "${SECRETS[@]}"; do
  printf '%s' "${!name}" | gh secret set "$name" --repo "$REPO"
  echo "  ✓ $name"
done
echo "완료 ✅  ($REPO → Settings → Secrets and variables → Actions 에서 확인 가능)"
