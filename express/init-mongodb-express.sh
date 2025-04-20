#!/bin/bash

# 명령어 실패 시 스크립트 종료
set -euo pipefail

# 로그 출력 함수
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 에러 발생 시 로그와 함께 종료하는 함수
error() {
  log "Error on line $1"
  exit 1
}

trap 'error $LINENO' ERR

log "스크립트 실행 시작."

# docker network 생성
if docker network ls --format '{{.Name}}' | grep -q '^nansan-network$'; then
  log "Docker network named 'nansan-network' is already existed."
else
  log "Docker network named 'nansan-network' is creating..."
  docker network create --driver bridge nansan-network
fi

cd express || { echo "디렉토리 변경 실패"; exit 1; }

# 실행중인 mongodb-express container 삭제
log "mongodb-express container remove."
docker rm -f mongodb-express

# 기존 mongodb-express 이미지를 삭제하고 새로 빌드
log "mongodb-express image remove and build."
docker rmi mongodb-express:latest || true
docker build -t mongodb-express:latest .

# 필요한 환경변수를 Vault에서 가져오기
log "Get credential data from vault..."

TOKEN_RESPONSES=$(curl -s --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\", \"secret_id\":\"${SECRET_ID}\"}" \
  https://vault.nansan.site/v1/auth/approle/login)

CLIENT_TOKEN=$(echo "$TOKEN_RESPONSES" | jq -r '.auth.client_token')

SECRET_RESPONSE=$(curl -s --header "X-Vault-Token: ${CLIENT_TOKEN}" \
  --request GET https://vault.nansan.site/v1/kv/data/authentication)

ME_CONFIG_MONGODB_ADMINUSERNAME=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.mongodb.username')
ME_CONFIG_MONGODB_ADMINPASSWORD=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.mongodb.password')
ME_CONFIG_BASICAUTH_USERNAME=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.express.username')
ME_CONFIG_BASICAUTH_PASSWORD=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.express.password')

# 비밀번호 인코딩
ENCODED_ME_CONFIG_MONGODB_ADMINPASSWORD=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "${ME_CONFIG_MONGODB_ADMINPASSWORD}")

# Docker로 mongodb-express 서비스 실행
log "Execute mongodb-express..."
docker run -d \
  --name mongodb-express \
  --restart unless-stopped \
  -v /var/mongodb-express:/var/log/mongo-express \
  -p 8082:8081 \
  -e ME_CONFIG_MONGODB_SERVER=mongodb \
  -e ME_CONFIG_MONGODB_PORT=27017 \
  -e ME_CONFIG_MONGODB_ADMINUSERNAME=${ME_CONFIG_MONGODB_ADMINUSERNAME} \
  -e ME_CONFIG_MONGODB_ADMINPASSWORD=${ENCODED_ME_CONFIG_MONGODB_ADMINPASSWORD} \
  -e ME_CONFIG_MONGODB_ENABLE_ADMIN=true \
  -e ME_CONFIG_BASICAUTH_USERNAME=${ME_CONFIG_BASICAUTH_USERNAME} \
  -e ME_CONFIG_BASICAUTH_PASSWORD=${ME_CONFIG_BASICAUTH_PASSWORD} \
  --network nansan-network \
  mongodb-express:latest

echo "작업이 완료되었습니다."
