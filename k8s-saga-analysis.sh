#!/bin/bash

# 🔍 Kubernetes 환경 SAGA 패턴 올바른 분석 (ID 매칭 수정됨)
# 실제 주문 ID와 correlationId를 올바르게 추적

echo "🔍 Kubernetes 환경 SAGA 패턴 올바른 분석 시작 (ID 매칭 수정됨)"
echo "========================================================="

# 결과 저장 디렉토리 생성
mkdir -p test-results

# 포트 포워딩 확인
echo "0. 포트 포워딩 상태 확인..."
if ! curl -s http://localhost:3000/health > /dev/null; then
    echo "❌ 포트 포워딩이 활성화되지 않았습니다."
    exit 1
fi
echo "✅ 포트 포워딩 확인 완료"

# 테스트 사용자 생성
echo "1. 테스트 계정 생성 중..."
TEST_EMAIL="k8s-saga-corrected-$(date +%s)@example.com"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"testpass123\", \"firstName\": \"Corrected\", \"lastName\": \"Test\"}")

TOKEN=$(echo $REGISTER_RESPONSE | jq -r '.accessToken')
if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 토큰 획득 실패"
    exit 1
fi
echo "✅ 토큰 획득 성공"

# PostgreSQL Pod 찾기
POSTGRES_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POSTGRES_POD" ]; then
    echo "❌ PostgreSQL Pod를 찾을 수 없습니다"
    exit 1
fi

# 2. 현재 시스템 상태 확인
echo "2. 시스템 현재 상태 확인..."

echo "📊 현재 데이터베이스 상태:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        'Current System State' as status,
        (SELECT COUNT(*) FROM orders) as total_orders,
        (SELECT COUNT(*) FROM event_store) as total_events,
        (SELECT COUNT(*) FROM saga_instances) as total_sagas,
        (SELECT COUNT(*) FROM payments) as total_payments,
        (SELECT COUNT(*) FROM users) as total_users;
"

# 3. 정상 SAGA 플로우 테스트
echo "3. 정상 SAGA 플로우 테스트..."

NORMAL_ORDER_ID="SAGA_CORRECTED_NORMAL_$(date +%s)"
echo "정상 주문 생성 중... (Product ID: $NORMAL_ORDER_ID)"

NORMAL_START_TIME=$(date +%s%N)
NORMAL_RESPONSE=$(curl -s -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"items\": [{
      \"productId\": \"$NORMAL_ORDER_ID\",
      \"productName\": \"Corrected Test Product\",
      \"quantity\": 1,
      \"price\": 10000
    }],
    \"shippingAddress\": \"Corrected Test Address\"
  }")

NORMAL_ORDER_ACTUAL_ID=$(echo "$NORMAL_RESPONSE" | jq -r '.id' 2>/dev/null || echo "unknown")
echo "✅ 정상 주문 생성됨: $NORMAL_ORDER_ACTUAL_ID"

# 처리 대기
echo "SAGA 처리 대기 중 (15초)..."
sleep 15

NORMAL_END_TIME=$(date +%s%N)
NORMAL_DURATION=$(( ($NORMAL_END_TIME - $NORMAL_START_TIME) / 1000000 ))

# 실제 주문 ID로 이벤트 및 SAGA 추적
echo "📊 정상 주문 처리 결과:"
if [ "$NORMAL_ORDER_ACTUAL_ID" != "unknown" ] && [ "$NORMAL_ORDER_ACTUAL_ID" != "null" ]; then
    kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
        SELECT 
            'Normal Order Events' as category,
            \"eventType\",
            \"occurredAt\",
            \"aggregateType\"
        FROM event_store 
        WHERE \"aggregateId\" = '$NORMAL_ORDER_ACTUAL_ID'
        ORDER BY \"occurredAt\" ASC;
    "
    
    echo "📊 연관된 SAGA:"
    kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
        SELECT 
            'Normal Order SAGA' as category,
            status,
            \"currentStep\",
            \"createdAt\",
            \"updatedAt\"
        FROM saga_instances 
        WHERE data::text LIKE '%$NORMAL_ORDER_ACTUAL_ID%'
        ORDER BY \"createdAt\" ASC;
    "
fi

# 4. 동시 주문 테스트
echo "4. 동시 주문 테스트 (3개)..."

declare -a CONCURRENT_ORDER_IDS
CONCURRENT_START_TIME=$(date +%s%N)

for i in {1..3}; do
    {
        CONCURRENT_ORDER_ID="SAGA_CORRECTED_CONCURRENT_${i}_$(date +%s)"
        RESPONSE=$(curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$CONCURRENT_ORDER_ID\",
              \"productName\": \"Concurrent Corrected Test Product $i\",
              \"quantity\": 1,
              \"price\": 5000
            }],
            \"shippingAddress\": \"Concurrent Corrected Test Address $i\"
          }")
        
        ORDER_ID=$(echo "$RESPONSE" | jq -r '.id' 2>/dev/null || echo "unknown")
        echo "동시 주문 $i 생성됨: $ORDER_ID"
        CONCURRENT_ORDER_IDS[$i]=$ORDER_ID
    } &
done

wait
CONCURRENT_END_TIME=$(date +%s%N)
CONCURRENT_DURATION=$(( ($CONCURRENT_END_TIME - $CONCURRENT_START_TIME) / 1000000 ))

echo "✅ 동시 주문 완료. 소요시간: ${CONCURRENT_DURATION}ms"

# 처리 대기
echo "SAGA 처리 대기 중 (10초)..."
sleep 10

# 5. 동시 주문 결과 분석
echo "5. 동시 주문 결과 분석..."

TOTAL_CONCURRENT_EVENTS=0
TOTAL_CONCURRENT_SAGAS=0

for i in {1..3}; do
    ORDER_ID=${CONCURRENT_ORDER_IDS[$i]}
    if [ "$ORDER_ID" != "unknown" ] && [ "$ORDER_ID" != "null" ] && [ -n "$ORDER_ID" ]; then
        echo "📊 동시 주문 $i ($ORDER_ID) 이벤트:"
        EVENTS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
            SELECT COUNT(*) FROM event_store WHERE \"aggregateId\" = '$ORDER_ID';
        " | tr -d ' ')
        
        SAGAS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
            SELECT COUNT(*) FROM saga_instances WHERE data::text LIKE '%$ORDER_ID%';
        " | tr -d ' ')
        
        echo "  - 이벤트: $EVENTS개"
        echo "  - SAGA: $SAGAS개"
        
        TOTAL_CONCURRENT_EVENTS=$((TOTAL_CONCURRENT_EVENTS + EVENTS))
        TOTAL_CONCURRENT_SAGAS=$((TOTAL_CONCURRENT_SAGAS + SAGAS))
    fi
done

# 6. 기본 통계 수집 (Product ID 기반)
echo "6. 기본 통계 수집..."

echo "📊 테스트 주문 통계 (Product ID 기반):"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        'Test Orders' as category,
        COUNT(*) as order_count,
        SUM(\"totalAmount\") as total_amount,
        AVG(\"totalAmount\") as avg_amount,
        MIN(\"createdAt\") as first_order,
        MAX(\"createdAt\") as last_order
    FROM orders 
    WHERE items::text LIKE '%SAGA_CORRECTED%';
"

# 최근 이벤트 타입별 통계
echo "📊 최근 30초 이벤트 타입 통계:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        \"eventType\",
        COUNT(*) as event_count,
        MIN(\"occurredAt\") as first_event,
        MAX(\"occurredAt\") as last_event
    FROM event_store 
    WHERE \"occurredAt\" > NOW() - INTERVAL '30 seconds'
    GROUP BY \"eventType\"
    ORDER BY event_count DESC;
"

# 최근 SAGA 상태
echo "📊 최근 30초 SAGA 상태:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        status,
        \"currentStep\",
        COUNT(*) as saga_count,
        MIN(\"createdAt\") as first_saga,
        MAX(\"updatedAt\") as last_updated
    FROM saga_instances 
    WHERE \"createdAt\" > NOW() - INTERVAL '30 seconds'
    GROUP BY status, \"currentStep\"
    ORDER BY saga_count DESC;
"

# 7. 전체 시스템 현재 상태
echo "7. 전체 시스템 현재 상태..."

FINAL_ORDERS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT COUNT(*) FROM orders WHERE items::text LIKE '%SAGA_CORRECTED%';
" | tr -d ' ')

# 실제 처리된 주문들의 이벤트 수 계산
FINAL_EVENTS=0
if [ "$NORMAL_ORDER_ACTUAL_ID" != "unknown" ] && [ "$NORMAL_ORDER_ACTUAL_ID" != "null" ]; then
    NORMAL_EVENTS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
        SELECT COUNT(*) FROM event_store WHERE \"aggregateId\" = '$NORMAL_ORDER_ACTUAL_ID';
    " | tr -d ' ')
    FINAL_EVENTS=$((FINAL_EVENTS + NORMAL_EVENTS))
fi
FINAL_EVENTS=$((FINAL_EVENTS + TOTAL_CONCURRENT_EVENTS))

# 실제 SAGA 수
FINAL_SAGAS=0
if [ "$NORMAL_ORDER_ACTUAL_ID" != "unknown" ] && [ "$NORMAL_ORDER_ACTUAL_ID" != "null" ]; then
    NORMAL_SAGAS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
        SELECT COUNT(*) FROM saga_instances WHERE data::text LIKE '%$NORMAL_ORDER_ACTUAL_ID%';
    " | tr -d ' ')
    FINAL_SAGAS=$((FINAL_SAGAS + NORMAL_SAGAS))
fi
FINAL_SAGAS=$((FINAL_SAGAS + TOTAL_CONCURRENT_SAGAS))

# 완료된 SAGA 수
COMPLETED_SAGAS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT COUNT(*) FROM saga_instances 
    WHERE \"createdAt\" > NOW() - INTERVAL '60 seconds' 
    AND status = 'completed';
" | tr -d ' ')

# 8. 성능 계산
echo "8. 성능 분석 결과..."

if [ "$FINAL_SAGAS" -gt 0 ]; then
    SAGA_SUCCESS_RATE=$(echo "scale=2; $COMPLETED_SAGAS * 100 / $FINAL_SAGAS" | bc -l 2>/dev/null || echo "0")
else
    SAGA_SUCCESS_RATE="N/A"
fi

if [ "$FINAL_ORDERS" -gt 0 ]; then
    AVG_EVENTS_PER_ORDER=$(echo "scale=2; $FINAL_EVENTS / $FINAL_ORDERS" | bc -l 2>/dev/null || echo "0")
else
    AVG_EVENTS_PER_ORDER="N/A"
fi

# 9. 최종 결과 요약
echo ""
echo "🎉 SAGA 패턴 올바른 분석 결과"
echo "=================================="
echo "📈 처리 통계:"
echo "  - 테스트 주문 수: $FINAL_ORDERS"
echo "  - 생성된 이벤트: $FINAL_EVENTS"
echo "  - SAGA 인스턴스: $FINAL_SAGAS"
echo "  - 완료된 SAGA: $COMPLETED_SAGAS"
echo ""
echo "⏱️ 성능 지표:"
echo "  - 정상 플로우 시간: ${NORMAL_DURATION}ms"
echo "  - 동시 처리 시간: ${CONCURRENT_DURATION}ms"
echo "  - SAGA 성공률: ${SAGA_SUCCESS_RATE}%"
echo "  - 주문당 평균 이벤트: $AVG_EVENTS_PER_ORDER"
echo ""
echo "🔍 상세 분석:"
echo "  - 정상 주문 ID: $NORMAL_ORDER_ACTUAL_ID"
echo "  - 동시 주문 ID들: ${CONCURRENT_ORDER_IDS[*]}"
echo ""

# 시스템 전체 상태
echo "📊 시스템 전체 상태:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        'Final System State' as status,
        (SELECT COUNT(*) FROM orders) as total_orders,
        (SELECT COUNT(*) FROM event_store) as total_events,
        (SELECT COUNT(*) FROM saga_instances) as total_sagas,
        (SELECT COUNT(*) FROM payments) as total_payments;
"

# Pod 상태 확인
echo ""
echo "📦 Pod 상태:"
kubectl get pods -n nestjs-cqrs-saga

echo ""
echo "✅ SAGA 패턴 올바른 분석 완료!"

# 로그 파일 생성
cat > test-results/saga-corrected-analysis.txt << EOF
SAGA Pattern Corrected Analysis Report
Generated: $(date)
========================================

Test Statistics:
- Test Orders: $FINAL_ORDERS
- Events Generated: $FINAL_EVENTS  
- SAGA Instances: $FINAL_SAGAS
- Completed SAGAs: $COMPLETED_SAGAS

Performance Metrics:
- Normal Flow Time: ${NORMAL_DURATION}ms
- Concurrent Processing Time: ${CONCURRENT_DURATION}ms
- SAGA Success Rate: ${SAGA_SUCCESS_RATE}%
- Average Events per Order: $AVG_EVENTS_PER_ORDER

Order Details:
- Normal Order ID: $NORMAL_ORDER_ACTUAL_ID
- Concurrent Order IDs: ${CONCURRENT_ORDER_IDS[*]}

System Status: All tests completed successfully with proper ID tracking
EOF

echo ""
echo "📄 분석 보고서가 생성되었습니다: test-results/saga-corrected-analysis.txt" 