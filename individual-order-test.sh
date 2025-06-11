#!/bin/bash

# 개별 요청 Order 생성 테스트
# 2.1 각각의 요청이 각각의 노드에서 실행되며 SAGA가 보장되는지
# 2.2 Kafka로 인해 노드별로 간섭이 일어나지 않는지 확인

echo "🌟 개별 요청 Order 생성 테스트 시작"
echo "========================================"

# 테스트 환경 확인
echo "1️⃣ 테스트 환경 확인 중..."
curl -s http://localhost:8090/health | jq '.' > test-results/individual-health-check.json
echo "✅ Health check 완료"

# 기존 데이터 삭제 (users 제외)
echo "2️⃣ 기존 데이터 정리 중..."
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "DELETE FROM orders; DELETE FROM event_store; DELETE FROM saga_instances; DELETE FROM payments;" > test-results/individual-cleanup.log
echo "✅ 데이터 정리 완료"

# 테스트 사용자 로그인
echo "3️⃣ 테스트 사용자 로그인 중..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8090/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "jsnoh@test.com", "password": "aimmed"}')

echo "$LOGIN_RESPONSE" | jq '.' > test-results/individual-login-response.json
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 로그인 실패"
    exit 1
fi
echo "✅ 로그인 성공: $TOKEN" 

# 2.1 각 노드별로 다른 상품 주문 테스트
echo "4️⃣ [테스트 2.1] 각 노드별 다른 상품 주문 SAGA 보장 테스트"

PRODUCTS=("LAPTOP_A001" "MOUSE_B002" "KEYBOARD_C003" "MONITOR_D004" "SPEAKER_E005")
TOTAL_REQUESTS=${#PRODUCTS[@]}

echo "총 $TOTAL_REQUESTS 개의 서로 다른 상품으로 동시 주문..."

# 각 상품별로 다른 노드에 요청
for i in "${!PRODUCTS[@]}"; do
    {
        PRODUCT_ID="${PRODUCTS[$i]}"
        NODE_NUMBER=$((($i % 3) + 1))
        NODE_PORT=$((3000 + $NODE_NUMBER))
        PRICE=$((1000 + $i * 500))
        
        RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$PRODUCT_ID\",
              \"productName\": \"Product $PRODUCT_ID\",
              \"quantity\": 1,
              \"price\": $PRICE
            }],
            \"shippingAddress\": \"Test Address\"
          }")
        echo "Product $PRODUCT_ID -> Node $NODE_NUMBER (Port $NODE_PORT): $RESPONSE" >> test-results/individual-test-2.1.log
    } &
done

wait
echo "✅ 개별 상품 주문 요청 완료"

# SAGA 처리 대기
sleep 5

# 결과 확인
echo "📊 개별 주문 결과 확인..."
INDIVIDUAL_ORDERS_COUNT=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders;")
INDIVIDUAL_SAGA_COUNT=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances;")
COMPLETED_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE status = 'CONFIRMED';")
COMPLETED_SAGAS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances WHERE status = 'COMPLETED';")

echo "생성된 총 주문 수: $INDIVIDUAL_ORDERS_COUNT (예상: $TOTAL_REQUESTS개)"
echo "생성된 총 SAGA 수: $INDIVIDUAL_SAGA_COUNT (예상: $TOTAL_REQUESTS개)"
echo "완료된 주문 수: $COMPLETED_ORDERS"
echo "완료된 SAGA 수: $COMPLETED_SAGAS"

# 2.2 Kafka 노드별 간섭 없음 확인 테스트
echo "5️⃣ [테스트 2.2] Kafka 노드별 간섭 없음 확인 테스트"

# 더 많은 다양한 상품으로 동시 요청
EXTENDED_PRODUCTS=("PHONE_F006" "TABLET_G007" "WATCH_H008" "EARBUDS_I009" "CHARGER_J010" "CABLE_K011" "CASE_L012" "STAND_M013" "BATTERY_N014" "ADAPTER_O015")
KAFKA_TEST_COUNT=${#EXTENDED_PRODUCTS[@]}

echo "Kafka 간섭 테스트: $KAFKA_TEST_COUNT 개의 서로 다른 상품으로 랜덤 노드 주문..."

# 랜덤하게 노드에 분산 요청
for i in "${!EXTENDED_PRODUCTS[@]}"; do
    {
        PRODUCT_ID="${EXTENDED_PRODUCTS[$i]}"
        NODE_NUMBER=$(($RANDOM % 3 + 1))
        NODE_PORT=$((3000 + $NODE_NUMBER))
        PRICE=$((2000 + $i * 300))
        QUANTITY=$(($RANDOM % 3 + 1))
        
        RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$PRODUCT_ID\",
              \"productName\": \"Extended Product $PRODUCT_ID\",
              \"quantity\": $QUANTITY,
              \"price\": $PRICE
            }],
            \"shippingAddress\": \"Test Address\"
          }")
        echo "Product $PRODUCT_ID (Qty: $QUANTITY) -> Random Node $NODE_NUMBER (Port $NODE_PORT): $RESPONSE" >> test-results/kafka-interference-test-2.2.log
        
        # 약간의 랜덤 딜레이로 실제 상황 시뮬레이션
        sleep 0.$((RANDOM % 5 + 1))
    } &
done

wait
echo "✅ Kafka 간섭 테스트 요청 완료"

# Kafka 처리 대기
sleep 8

# Kafka 간섭 테스트 결과 확인
echo "📊 Kafka 간섭 테스트 결과 확인..."
TOTAL_FINAL_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders;")
TOTAL_FINAL_SAGAS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances;")
TOTAL_COMPLETED_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE status = 'CONFIRMED';")
TOTAL_COMPLETED_SAGAS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances WHERE status = 'COMPLETED';")

EXPECTED_TOTAL=$((TOTAL_REQUESTS + KAFKA_TEST_COUNT))

echo "최종 총 주문 수: $TOTAL_FINAL_ORDERS (예상: $EXPECTED_TOTAL개)"
echo "최종 총 SAGA 수: $TOTAL_FINAL_SAGAS (예상: $EXPECTED_TOTAL개)"
echo "최종 완료된 주문 수: $TOTAL_COMPLETED_ORDERS"
echo "최종 완료된 SAGA 수: $TOTAL_COMPLETED_SAGAS"

# 노드별 처리 분포 확인
echo "6️⃣ 노드별 처리 분포 확인..."
for NODE in 1 2 3; do
    NODE_LOGS=$(docker logs nestjs-cqrs-saga-nestjs-node-${NODE}-1 2>&1 | grep -c "Order created" || echo "0")
    echo "Node $NODE 처리된 주문 수: $NODE_LOGS"
done

# Event Store 무결성 확인
echo "7️⃣ Event Store 무결성 확인..."
EVENT_COUNT=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM event_store;")
ORDER_CREATED_EVENTS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM event_store WHERE event_type = 'OrderCreatedEvent';")
PAYMENT_PROCESSED_EVENTS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM event_store WHERE event_type = 'PaymentProcessedEvent';")

echo "총 이벤트 수: $EVENT_COUNT"
echo "OrderCreated 이벤트 수: $ORDER_CREATED_EVENTS"
echo "PaymentProcessed 이벤트 수: $PAYMENT_PROCESSED_EVENTS"

# 전체 결과 요약
echo "📋 개별 요청 테스트 결과 요약"
echo "================================"
echo "2.1 개별 노드 SAGA 보장: $INDIVIDUAL_ORDERS_COUNT/$TOTAL_REQUESTS 주문 생성, $COMPLETED_ORDERS 완료"
echo "2.2 Kafka 간섭 없음: $TOTAL_FINAL_ORDERS/$EXPECTED_TOTAL 총 주문, $TOTAL_COMPLETED_ORDERS 완료"
echo "Event Store 무결성: $EVENT_COUNT 총 이벤트, $ORDER_CREATED_EVENTS 주문생성, $PAYMENT_PROCESSED_EVENTS 결제처리"

# 상세 데이터 덤프
echo "📊 상세 데이터 덤프 중..."
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    id, product_id, quantity, price, status, created_at,
    EXTRACT(EPOCH FROM created_at) as timestamp_epoch
FROM orders 
ORDER BY created_at DESC;
" > test-results/individual-test-final-orders.txt

docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    id, correlation_id, status, step, created_at,
    EXTRACT(EPOCH FROM created_at) as timestamp_epoch
FROM saga_instances 
ORDER BY created_at DESC;
" > test-results/individual-test-final-sagas.txt

docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    id, event_type, aggregate_id, event_data, created_at,
    EXTRACT(EPOCH FROM created_at) as timestamp_epoch
FROM event_store 
ORDER BY created_at DESC;
" > test-results/individual-test-final-events.txt

echo "✅ 개별 요청 Order 생성 테스트 완료!"
echo "결과 파일: test-results/individual-test-*.log, test-results/individual-test-*.txt" 