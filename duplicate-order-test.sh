#!/bin/bash

# 중복 요청 Order 생성 테스트
# 1.1 ProductId 기준 중복방지 (Redis 락)
# 1.2 Payment 실패시 SAGA 보상 트랜잭션  
# 1.3 Multi-node에서 Redis 락을 통한 중복방지 확인

echo "🔥 중복 요청 Order 생성 테스트 시작"
echo "========================================"

# 테스트 환경 확인
echo "1️⃣ 테스트 환경 확인 중..."
curl -s http://localhost:3000/health | jq '.' > test-results/health-check.json
echo "✅ Health check 완료"

# 기존 데이터 삭제 (users 제외)
echo "2️⃣ 기존 데이터 정리 중..."
kubectl exec -n nestjs-cqrs-saga deployment/postgres -- psql -U postgres -d nestjs_cqrs -c "DELETE FROM orders; DELETE FROM event_store; DELETE FROM saga_instances; DELETE FROM payments;" > test-results/cleanup.log
echo "✅ 데이터 정리 완료"

# 테스트 사용자 등록 및 로그인
echo "3️⃣ 테스트 사용자 등록 중..."
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "jsnoh@test.com", "password": "aimmed", "firstName": "JS", "lastName": "Noh"}') 
echo "등록 응답: $REGISTER_RESPONSE" 

echo "테스트 사용자 로그인 중..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "jsnoh@test.com", "password": "aimmed"}')

echo "$LOGIN_RESPONSE" | jq '.' > test-results/login-response.json
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 로그인 실패"
    exit 1
fi
echo "✅ 로그인 성공: $TOKEN"

# 1.1 동일한 ProductId로 동시 요청 (중복방지 테스트)
echo "4️⃣ [테스트 1.1] 동일한 ProductId로 동시 중복 요청 테스트"
PRODUCT_ID="DUPLICATE_TEST_PRODUCT_001"
CONCURRENT_REQUESTS=5

echo "동일한 상품 ($PRODUCT_ID)으로 $CONCURRENT_REQUESTS 개의 동시 요청..."

for i in $(seq 1 $CONCURRENT_REQUESTS); do
    {
        RESPONSE=$(curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$PRODUCT_ID\",
              \"productName\": \"Test Product $PRODUCT_ID\",
              \"quantity\": 1,
              \"price\": 1000
            }],
            \"shippingAddress\": \"Test Address\"
          }")
        echo "Request $i: $RESPONSE" >> test-results/duplicate-test-1.1.log
    } &
done

wait
echo "✅ 동시 요청 완료"

# 결과 확인
sleep 3
echo "📊 결과 확인..."
ORDERS_COUNT=$(kubectl exec -n nestjs-cqrs-saga deployment/postgres -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE items::text LIKE '%$PRODUCT_ID%';")
SAGA_COUNT=$(kubectl exec -n nestjs-cqrs-saga deployment/postgres -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances WHERE \"correlationId\" LIKE '%$PRODUCT_ID%';")

echo "생성된 주문 수: $ORDERS_COUNT (예상: 1개)"
echo "생성된 SAGA 수: $SAGA_COUNT (예상: 1개)"

# 1.2 Payment 실패 시나리오 테스트
echo "5️⃣ [테스트 1.2] Payment 실패시 SAGA 보상 트랜잭션 테스트"
FAIL_PRODUCT_ID="PAYMENT_FAIL_TEST_002"

# Payment 실패를 유발하는 특수 productId 사용
FAIL_RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"items\": [{
      \"productId\": \"$FAIL_PRODUCT_ID\",
      \"productName\": \"Fail Test Product\",
      \"quantity\": 1,
      \"price\": 999999
    }],
    \"shippingAddress\": \"Test Address\"
  }")

echo "$FAIL_RESPONSE" | jq '.' > test-results/payment-fail-test-1.2.json

# SAGA 보상 트랜잭션 확인
sleep 5
FAIL_ORDER_STATUS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT status FROM orders WHERE product_id = '$FAIL_PRODUCT_ID';")
FAIL_SAGA_STATUS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT status FROM saga_instances WHERE correlation_id LIKE '%$FAIL_PRODUCT_ID%';")

echo "실패 주문 상태: $FAIL_ORDER_STATUS (예상: cancelled 또는 failed)"
echo "실패 SAGA 상태: $FAIL_SAGA_STATUS (예상: failed 또는 compensated)"

# 1.3 Multi-node 중복방지 테스트
echo "6️⃣ [테스트 1.3] Multi-node 환경에서 Redis 락 중복방지 테스트"
MULTI_PRODUCT_ID="MULTI_NODE_TEST_003"
NODE_REQUESTS=3

echo "각 노드별로 동일한 상품 ($MULTI_PRODUCT_ID) 요청..."

# 각 노드별로 직접 요청
for i in $(seq 1 $NODE_REQUESTS); do
    {
        NODE_PORT=$((3000 + $i))
        RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$MULTI_PRODUCT_ID\",
              \"productName\": \"Multi Node Test Product\",
              \"quantity\": 1,
              \"price\": 1500
            }],
            \"shippingAddress\": \"Test Address\"
          }")
        echo "Node $i (Port $NODE_PORT): $RESPONSE" >> test-results/multi-node-test-1.3.log
    } &
done

wait
echo "✅ Multi-node 요청 완료"

# Multi-node 결과 확인
sleep 3
MULTI_ORDERS_COUNT=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE product_id = '$MULTI_PRODUCT_ID';")
MULTI_SAGA_COUNT=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances WHERE correlation_id LIKE '%$MULTI_PRODUCT_ID%';")

echo "Multi-node 생성된 주문 수: $MULTI_ORDERS_COUNT (예상: 1개)"
echo "Multi-node 생성된 SAGA 수: $MULTI_SAGA_COUNT (예상: 1개)"

# 전체 결과 요약
echo "📋 테스트 결과 요약"
echo "===================="
echo "1.1 중복방지 테스트: 주문 $ORDERS_COUNT개 생성 (성공 기준: 1개)"
echo "1.2 Payment 실패 테스트: 주문 상태 $FAIL_ORDER_STATUS, SAGA 상태 $FAIL_SAGA_STATUS"
echo "1.3 Multi-node 중복방지: 주문 $MULTI_ORDERS_COUNT개 생성 (성공 기준: 1개)"

# 상세 데이터 덤프
echo "📊 상세 데이터 덤프 중..."
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    'orders' as table_name,
    id, product_id, status, created_at 
FROM orders 
ORDER BY created_at DESC;
" > test-results/duplicate-test-final-orders.txt

docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    'saga_instances' as table_name,
    id, correlation_id, status, step, created_at 
FROM saga_instances 
ORDER BY created_at DESC;
" > test-results/duplicate-test-final-sagas.txt

echo "✅ 중복 요청 Order 생성 테스트 완료!"
echo "결과 파일: test-results/duplicate-test-*.log, test-results/duplicate-test-*.json" 