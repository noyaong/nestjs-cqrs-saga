#!/bin/bash

# DB 기반 실제 노드 분산 분석
echo "📊 DB 기반 실제 노드 분산 분석"
echo "=============================="

echo "1️⃣ 마이크로초 단위 타임스탬프 분석..."

# 동시 생성된 주문들의 정확한 시간 분석
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    id,
    items::text as product_info,
    \"createdAt\",
    EXTRACT(EPOCH FROM \"createdAt\") as timestamp_epoch,
    EXTRACT(MICROSECONDS FROM \"createdAt\") as microseconds,
    LAG(EXTRACT(EPOCH FROM \"createdAt\")) OVER (ORDER BY \"createdAt\") as prev_timestamp,
    EXTRACT(EPOCH FROM \"createdAt\") - LAG(EXTRACT(EPOCH FROM \"createdAt\")) OVER (ORDER BY \"createdAt\") as time_diff
FROM orders 
ORDER BY \"createdAt\" ASC;
" > test-results/timestamp-analysis.txt

echo "2️⃣ 동시 처리 그룹 분석..."

# 0.1초 이내 생성된 주문들을 동시 처리 그룹으로 분류
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
WITH time_groups AS (
    SELECT 
        id,
        items::text as product_info,
        \"createdAt\",
        EXTRACT(EPOCH FROM \"createdAt\") as timestamp_epoch,
        FLOOR(EXTRACT(EPOCH FROM \"createdAt\") / 0.1) as time_group
    FROM orders 
    ORDER BY \"createdAt\"
),
group_stats AS (
    SELECT 
        time_group,
        COUNT(*) as concurrent_requests,
        MIN(timestamp_epoch) as group_start,
        MAX(timestamp_epoch) as group_end,
        MAX(timestamp_epoch) - MIN(timestamp_epoch) as group_duration
    FROM time_groups
    GROUP BY time_group
    HAVING COUNT(*) > 1
)
SELECT 
    tg.time_group,
    tg.id,
    tg.product_info,
    tg.timestamp_epoch,
    gs.concurrent_requests,
    gs.group_duration,
    ROW_NUMBER() OVER (PARTITION BY tg.time_group ORDER BY tg.timestamp_epoch) as processing_order
FROM time_groups tg
JOIN group_stats gs ON tg.time_group = gs.time_group
ORDER BY tg.time_group, tg.timestamp_epoch;
" > test-results/concurrent-groups.txt

echo "3️⃣ 추정 노드 분산 계산..."

# 동시 요청을 처리 순서로 노드 추정
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
WITH ordered_requests AS (
    SELECT 
        id,
        items::text as product_info,
        \"createdAt\",
        EXTRACT(EPOCH FROM \"createdAt\") as timestamp_epoch,
        ROW_NUMBER() OVER (ORDER BY \"createdAt\") as creation_order
    FROM orders
),
estimated_nodes AS (
    SELECT 
        *,
        CASE 
            WHEN creation_order % 3 = 1 THEN 'Node-1'
            WHEN creation_order % 3 = 2 THEN 'Node-2'
            ELSE 'Node-3'
        END as estimated_node
    FROM ordered_requests
)
SELECT 
    estimated_node,
    COUNT(*) as processed_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders), 2) as percentage,
    STRING_AGG(SUBSTRING(product_info FROM '\"productId\":\"([^\"]+)\"'), ', ') as products
FROM estimated_nodes
GROUP BY estimated_node
ORDER BY estimated_node;
" > test-results/estimated-distribution.txt

echo "4️⃣ 실시간 분산 테스트 실행..."

# 새로운 요청으로 실시간 분산 확인
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8090/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "jsnoh@test.com", "password": "aimmed"}')

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken')

echo "토큰 획득: $TOKEN"

# 10개 동시 요청으로 실시간 분산 테스트
PRODUCTS=("TEST_A" "TEST_B" "TEST_C" "TEST_D" "TEST_E" "TEST_F" "TEST_G" "TEST_H" "TEST_I" "TEST_J")

echo "10개 동시 요청 실행..."
for i in "${!PRODUCTS[@]}"; do
    {
        START_TIME=$(date +%s.%N)
        RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"${PRODUCTS[$i]}\",
              \"productName\": \"Test Product ${PRODUCTS[$i]}\",
              \"quantity\": 1,
              \"price\": 1000
            }],
            \"shippingAddress\": \"Test Address\"
          }")
        END_TIME=$(date +%s.%N)
        
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        echo "Product ${PRODUCTS[$i]}: 응답시간 ${DURATION}초, 응답: $RESPONSE" >> test-results/realtime-test.log
    } &
done

wait
sleep 3

echo "5️⃣ 실시간 테스트 결과 분석..."

# 실시간 테스트 결과 DB 분석
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
WITH recent_orders AS (
    SELECT 
        id,
        items::text as product_info,
        \"createdAt\",
        EXTRACT(EPOCH FROM \"createdAt\") as timestamp_epoch
    FROM orders
    WHERE items::text LIKE '%TEST_%'
    ORDER BY \"createdAt\"
),
processing_sequence AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY timestamp_epoch) as sequence,
        CASE 
            WHEN ROW_NUMBER() OVER (ORDER BY timestamp_epoch) % 3 = 1 THEN 'Node-1'
            WHEN ROW_NUMBER() OVER (ORDER BY timestamp_epoch) % 3 = 2 THEN 'Node-2'
            ELSE 'Node-3'
        END as likely_node
    FROM recent_orders
)
SELECT 
    sequence,
    SUBSTRING(product_info FROM '\"productId\":\"([^\"]+)\"') as product_id,
    timestamp_epoch,
    likely_node,
    timestamp_epoch - LAG(timestamp_epoch) OVER (ORDER BY sequence) as time_gap
FROM processing_sequence
ORDER BY sequence;
" > test-results/realtime-distribution.txt

echo ""
echo "📋 분석 결과 요약"
echo "================"

echo "🔍 추정 노드 분산:"
cat test-results/estimated-distribution.txt

echo ""
echo "🔍 실시간 테스트 분산:"
cat test-results/realtime-distribution.txt

echo ""
echo "✅ 분석 완료!"
echo "📂 상세 결과 파일들:"
echo "  - test-results/timestamp-analysis.txt"
echo "  - test-results/concurrent-groups.txt" 
echo "  - test-results/estimated-distribution.txt"
echo "  - test-results/realtime-distribution.txt"
echo "  - test-results/realtime-test.log" 