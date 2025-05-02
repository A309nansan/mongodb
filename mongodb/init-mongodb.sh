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

# 실행중인 mongodb container 삭제
log "mongodb container remove."
docker rm -f mongodb

# 기존 mongodb 이미지를 삭제하고 새로 빌드
log "mongodb image remove and build."
docker rmi mongodb:latest || true
docker build -t mongodb:latest .

# 필요한 환경변수를 Vault에서 가져오기
log "Get credential data from vault..."

TOKEN_RESPONSES=$(curl -s --request POST \
  --data "{\"role_id\":\"${ROLE_ID}\", \"secret_id\":\"${SECRET_ID}\"}" \
  https://vault.nansan.site/v1/auth/approle/login)

CLIENT_TOKEN=$(echo "$TOKEN_RESPONSES" | jq -r '.auth.client_token')

SECRET_RESPONSE=$(curl -s --header "X-Vault-Token: ${CLIENT_TOKEN}" \
  --request GET https://vault.nansan.site/v1/kv/data/authentication)

MONGODB_INITDB_ROOT_USERNAME=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.mongodb.username')
MONGODB_INITDB_ROOT_PASSWORD=$(echo "$SECRET_RESPONSE" | jq -r '.data.data.mongodb.password')

# Docker로 mongodb 서비스 실행
log "Execute mongodb..."
docker run -d \
  --name mongodb \
  --restart unless-stopped \
  -v /var/mongodb:/data/db \
  -v /var/mongodb/log:/var/log/mongodb \
  -e MONGODB_INITDB_ROOT_USERNAME=${MONGODB_INITDB_ROOT_USERNAME} \
  -e MONGODB_INITDB_ROOT_PASSWORD=${MONGODB_INITDB_ROOT_PASSWORD} \
  -p 11101:27019
  --network nansan-network \
  mongodb:latest

echo "작업이 완료되었습니다."
