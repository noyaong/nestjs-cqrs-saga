#!/bin/bash

# 혼합 테스트 (중복요청+개별요청 다수)
# 3.1 위의 케이스를 모두 충족하는지 확인

echo "🚀 혼합 테스트 (중복 + 개별 요청) 시작"
echo "========================================"

# 테스트 환경 확인
echo "1️⃣ 테스트 환경 확인 중..."
curl -s http://localhost:8090/health | jq '.' > test-results/mixed-health-check.json
echo "✅ Health check 완료"

# 기존 데이터 삭제 (users 제외)
echo "2️⃣ 기존 데이터 정리 중..."
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "DELETE FROM orders; DELETE FROM event_store; DELETE FROM saga_instances; DELETE FROM payments;" > test-results/mixed-cleanup.log
echo "✅ 데이터 정리 완료"

# 테스트 사용자 로그인
echo "3️⃣ 테스트 사용자 로그인 중..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8090/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "jsnoh@test.com", "password": "aimmed"}')

echo "$LOGIN_RESPONSE" | jq '.' > test-results/mixed-login-response.json
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken') 

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 로그인 실패"
    exit 1
fi
echo "✅ 로그인 성공: $TOKEN"

# 3.1 혼합 시나리오 테스트
echo "4️⃣ [테스트 3.1] 혼합 시나리오 테스트 시작"

# 중복 요청할 상품들 (각각 다수 요청)
DUPLICATE_PRODUCTS=("HOT_ITEM_001" "LIMITED_EDITION_002" "SALE_SPECIAL_003")

# 개별 요청할 상품들 (각각 한번만)
INDIVIDUAL_PRODUCTS=("UNIQUE_A001" "UNIQUE_B002" "UNIQUE_C003" "UNIQUE_D004" "UNIQUE_E005")

echo "혼합 테스트 시작:"
echo "- 중복 상품 ${#DUPLICATE_PRODUCTS[@]}개 (각각 3-5회 중복 요청)"
echo "- 개별 상품 ${#INDIVIDUAL_PRODUCTS[@]}개 (각각 1회)"

# 1. 중복 요청 시뮬레이션 (Background로 실행)
echo "🔄 중복 요청 시뮬레이션 시작..."
for PRODUCT in "${DUPLICATE_PRODUCTS[@]}"; do
    DUPLICATE_COUNT=$((3 + RANDOM % 3))  # 3-5개 중복 요청
    echo "상품 $PRODUCT: $DUPLICATE_COUNT 개 중복 요청"
    
    for j in $(seq 1 $DUPLICATE_COUNT); do
        {
            PRICE=$((5000 + RANDOM % 3000))
            
            RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer $TOKEN" \
              -d "{
                \"items\": [{
                  \"productId\": \"$PRODUCT\",
                  \"productName\": \"Duplicate Product $PRODUCT\",
                  \"quantity\": 1,
                  \"price\": $PRICE
                }],
                \"shippingAddress\": \"Test Address\"
              }")
            echo "DUPLICATE - $PRODUCT Request $j: $RESPONSE" >> test-results/mixed-duplicate-requests.log
        } &
    done
done

# 2. 개별 요청 시뮬레이션 (Background로 실행)
echo "🎯 개별 요청 시뮬레이션 시작..."
for i in "${!INDIVIDUAL_PRODUCTS[@]}"; do
    {
        PRODUCT="${INDIVIDUAL_PRODUCTS[$i]}"
        PRICE=$((1000 + $i * 200))
        QUANTITY=$(($RANDOM % 3 + 1))
        
        RESPONSE=$(curl -s -X POST http://localhost:8090/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$PRODUCT\",
              \"productName\": \"Individual Product $PRODUCT\",
              \"quantity\": $QUANTITY,
              \"price\": $PRICE
            }],
            \"shippingAddress\": \"Test Address\"
          }")
        echo "INDIVIDUAL - $PRODUCT (Qty: $QUANTITY): $RESPONSE" >> test-results/mixed-individual-requests.log
        
        # 랜덤 딜레이
        sleep 0.$((RANDOM % 3 + 1))
    } &
done

echo "모든 요청 실행 중... 처리 대기 중"
wait

echo "✅ 모든 혼합 요청 완료"

# SAGA 및 보상 트랜잭션 처리 대기
echo "⏳ SAGA 처리 및 보상 트랜잭션 대기 중..."
sleep 8

# 5️⃣ 결과 분석
echo "5️⃣ 혼합 테스트 결과 분석"

# 전체 통계
TOTAL_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders;")
TOTAL_SAGAS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances;")

# 상태별 통계
PAID_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE status = 'paid';")
PENDING_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE status = 'pending';")

COMPLETED_SAGAS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances WHERE status = 'completed';")

# 중복 요청 결과 확인
echo "📊 중복 요청 결과 확인..."
for PRODUCT in "${DUPLICATE_PRODUCTS[@]}"; do
    PRODUCT_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE items::text LIKE '%$PRODUCT%';")
    echo "$PRODUCT: $PRODUCT_ORDERS 개 주문 생성 (중복방지 확인: 1개 예상)"
done

# 개별 요청 결과 확인
echo "📊 개별 요청 결과 확인..."
INDIVIDUAL_SUCCESS=0
for PRODUCT in "${INDIVIDUAL_PRODUCTS[@]}"; do
    PRODUCT_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE items::text LIKE '%$PRODUCT%';")
    if [ "$PRODUCT_ORDERS" -eq 1 ]; then
        INDIVIDUAL_SUCCESS=$((INDIVIDUAL_SUCCESS + 1))
    fi
    echo "$PRODUCT: $PRODUCT_ORDERS 개 주문"
done

# Event Store 무결성 확인
EVENT_COUNT=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM event_store;")

# 6️⃣ 최종 결과 요약
echo "📋 혼합 테스트 최종 결과 요약"
echo "================================"
echo "🔢 전체 통계:"
echo "  - 총 주문 수: $TOTAL_ORDERS"
echo "  - 총 SAGA 수: $TOTAL_SAGAS"
echo ""
echo "📊 주문 상태 분포:"
echo "  - 결제완료 주문: $PAID_ORDERS"
echo "  - 대기중 주문: $PENDING_ORDERS"
echo ""
echo "🔄 SAGA 상태 분포:"
echo "  - 완료된 SAGA: $COMPLETED_SAGAS"
echo ""
echo "✅ 기능별 검증 결과:"
echo "  - 중복 요청 방지: ${#DUPLICATE_PRODUCTS[@]}개 상품 테스트 (각각 1개씩만 생성되어야 함)"
echo "  - 개별 요청 처리: $INDIVIDUAL_SUCCESS/${#INDIVIDUAL_PRODUCTS[@]}개 성공"
echo ""
echo "🎯 Event Store 무결성:"
echo "  - 총 이벤트: $EVENT_COUNT"

# 상세 데이터 덤프
echo "📊 상세 데이터 덤프 중..."

# 전체 주문 상세 정보
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    id, \"totalAmount\", status, items, \"createdAt\"
FROM orders 
ORDER BY \"createdAt\" DESC;
" > test-results/mixed-test-final-orders.txt

# SAGA 상세 정보
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    id, \"correlationId\", status, \"createdAt\", \"updatedAt\"
FROM saga_instances 
ORDER BY \"createdAt\" DESC;
" > test-results/mixed-test-final-sagas.txt

echo "✅ 혼합 테스트 완료!"
echo "📂 결과 파일들:"
echo "  - test-results/mixed-duplicate-requests.log"
echo "  - test-results/mixed-individual-requests.log"
echo "  - test-results/mixed-test-final-*.txt" 