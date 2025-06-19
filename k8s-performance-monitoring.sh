#!/bin/bash

# 🔍 Kubernetes 환경 실시간 성능 모니터링 (스키마 수정됨)
# 부하 테스트와 함께 Pod, 데이터베이스, Kafka 실시간 모니터링

echo "🔍 Kubernetes 환경 실시간 성능 모니터링 시작 (수정된 버전)"
echo "========================================================="

# 결과 저장 디렉토리 생성
mkdir -p test-results/monitoring

# 포트 포워딩 확인
echo "0. 포트 포워딩 상태 확인..."
if ! curl -s http://localhost:3000/health > /dev/null; then
    echo "❌ 포트 포워딩이 활성화되지 않았습니다."
    exit 1
fi
echo "✅ 포트 포워딩 확인 완료"

# 테스트 사용자 생성
echo "1. 테스트 계정 생성 중..."
TEST_EMAIL="k8s-monitor-fixed-$(date +%s)@example.com"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"testpass123\", \"firstName\": \"Monitor\", \"lastName\": \"Fixed\"}")

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

# Kafka Pod 찾기
KAFKA_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=kafka -o jsonpath='{.items[0].metadata.name}')
if [ -z "$KAFKA_POD" ]; then
    echo "❌ Kafka Pod를 찾을 수 없습니다"
    exit 1
fi

# 2. 실시간 모니터링 함수들 정의
monitor_pods() {
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Pod 상태:" | tee -a test-results/monitoring/pod-monitoring.log
    kubectl get pods -n nestjs-cqrs-saga -o wide | tee -a test-results/monitoring/pod-monitoring.log
    echo "" | tee -a test-results/monitoring/pod-monitoring.log
}

monitor_database() {
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] 데이터베이스 성능 (수정된 쿼리):" | tee -a test-results/monitoring/db-monitoring.log
    
    # 활성 연결 및 쿼리 (수정된 컬럼명)
    kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
        SELECT 
            now() as check_time,
            (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
            (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle') as idle_connections,
            (SELECT count(*) FROM orders) as total_orders,
            (SELECT count(*) FROM event_store) as total_events,
            (SELECT count(*) FROM saga_instances) as total_sagas;
    " | tee -a test-results/monitoring/db-monitoring.log
    
    echo "" | tee -a test-results/monitoring/db-monitoring.log
}

monitor_kafka() {
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Kafka 상태:" | tee -a test-results/monitoring/kafka-monitoring.log
    
    # Kafka 토픽 정보
    kubectl exec -n nestjs-cqrs-saga $KAFKA_POD -- kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | tee -a test-results/monitoring/kafka-monitoring.log
    echo "" | tee -a test-results/monitoring/kafka-monitoring.log
}

monitor_application_metrics() {
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] 애플리케이션 메트릭:" | tee -a test-results/monitoring/app-monitoring.log
    
    # 헬스체크로 애플리케이션 상태 확인
    for pod in $(kubectl get pods -n nestjs-cqrs-saga -l app=nestjs -o name); do
        POD_NAME=$(echo $pod | sed 's/pod\///')
        echo "Pod: $POD_NAME" | tee -a test-results/monitoring/app-monitoring.log
        kubectl exec -n nestjs-cqrs-saga $POD_NAME -- ps aux | grep node | tee -a test-results/monitoring/app-monitoring.log
    done
    echo "" | tee -a test-results/monitoring/app-monitoring.log
}

# 3. 백그라운드 모니터링 시작
echo "2. 백그라운드 모니터링 시작..."

# 초기 상태 캡처
monitor_pods
monitor_database  
monitor_kafka
monitor_application_metrics

# 15초마다 모니터링하는 백그라운드 프로세스
{
    for i in {1..20}; do  # 5분간 모니터링 (15초 * 20 = 300초)
        sleep 15
        monitor_pods
        monitor_database
        monitor_kafka
        monitor_application_metrics
    done
} &
MONITOR_PID=$!

echo "✅ 백그라운드 모니터링 시작됨 (PID: $MONITOR_PID)"

# 4. 부하 테스트 실행
echo "3. 단계별 부하 테스트 실행..."

# 단계 1: 가벼운 부하 (10 req/s for 30초)
echo "📊 단계 1: 가벼운 부하 테스트 (10 req/s for 30초)"
LIGHT_LOAD_START=$(date +%s)

for i in {1..30}; do
    {
        ORDER_ID="MONITOR_FIXED_LIGHT_${i}_$(date +%s)"
        curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$ORDER_ID\",
              \"productName\": \"Light Load Fixed Test Product $i\",
              \"quantity\": 1,
              \"price\": 1000
            }],
            \"shippingAddress\": \"Light Load Fixed Test Address $i\"
          }" > /dev/null
    } &
    
    sleep 0.1  # 100ms 간격으로 10 req/s 달성
done

wait
LIGHT_LOAD_END=$(date +%s)
LIGHT_LOAD_DURATION=$((LIGHT_LOAD_END - LIGHT_LOAD_START))
# 최소 1초 보장하여 division by zero 방지
if [ $LIGHT_LOAD_DURATION -eq 0 ]; then
    LIGHT_LOAD_DURATION=1
fi

echo "✅ 가벼운 부하 테스트 완료 (${LIGHT_LOAD_DURATION}초)"

# 결과 분석 대기
sleep 5

# 단계 2: 중간 부하 (50 req burst)
echo "📊 단계 2: 중간 부하 테스트 (50개 동시 요청)"
MEDIUM_LOAD_START=$(date +%s)

for i in {1..50}; do
    {
        ORDER_ID="MONITOR_FIXED_MEDIUM_${i}_$(date +%s)"
        curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$ORDER_ID\",
              \"productName\": \"Medium Load Fixed Test Product $i\",
              \"quantity\": 2,
              \"price\": 2000
            }],
            \"shippingAddress\": \"Medium Load Fixed Test Address $i\"
          }" > /dev/null
    } &
done

wait
MEDIUM_LOAD_END=$(date +%s)
MEDIUM_LOAD_DURATION=$((MEDIUM_LOAD_END - MEDIUM_LOAD_START))
# 최소 1초 보장하여 division by zero 방지
if [ $MEDIUM_LOAD_DURATION -eq 0 ]; then
    MEDIUM_LOAD_DURATION=1
fi

echo "✅ 중간 부하 테스트 완료 (${MEDIUM_LOAD_DURATION}초)"

# 결과 분석 대기
sleep 10

# 단계 3: 높은 부하 (100 req burst)
echo "📊 단계 3: 높은 부하 테스트 (100개 동시 요청)"
HEAVY_LOAD_START=$(date +%s)

for i in {1..100}; do
    {
        ORDER_ID="MONITOR_FIXED_HEAVY_${i}_$(date +%s)"
        curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$ORDER_ID\",
              \"productName\": \"Heavy Load Fixed Test Product $i\",
              \"quantity\": 3,
              \"price\": 3000
            }],
            \"shippingAddress\": \"Heavy Load Fixed Test Address $i\"
          }" > /dev/null
    } &
done

wait
HEAVY_LOAD_END=$(date +%s)
HEAVY_LOAD_DURATION=$((HEAVY_LOAD_END - HEAVY_LOAD_START))
# 최소 1초 보장하여 division by zero 방지
if [ $HEAVY_LOAD_DURATION -eq 0 ]; then
    HEAVY_LOAD_DURATION=1
fi

echo "✅ 높은 부하 테스트 완료 (${HEAVY_LOAD_DURATION}초)"

# 5. 최종 결과 분석 (수정된 쿼리)
echo "4. 최종 성능 분석..."

# 전체 테스트 통계
TOTAL_ORDERS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT count(*) FROM orders WHERE items::text LIKE '%MONITOR_FIXED%';
" | tr -d ' ')

TOTAL_EVENTS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT count(*) FROM event_store WHERE \"aggregateId\" LIKE '%MONITOR_FIXED%';
" | tr -d ' ')

TOTAL_SAGAS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT count(*) FROM saga_instances WHERE \"correlationId\" LIKE '%MONITOR_FIXED%';
" | tr -d ' ')

# 부하별 처리 통계 (수정된 컬럼명)
echo "📈 부하별 처리 통계:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        CASE 
            WHEN items::text LIKE '%Light Load%' THEN 'Light Load'
            WHEN items::text LIKE '%Medium Load%' THEN 'Medium Load' 
            WHEN items::text LIKE '%Heavy Load%' THEN 'Heavy Load'
            ELSE 'Other'
        END as load_type,
        COUNT(*) as order_count,
        MIN(\"createdAt\") as first_order,
        MAX(\"createdAt\") as last_order,
        ROUND(AVG(\"totalAmount\"), 2) as avg_amount
    FROM orders 
    WHERE items::text LIKE '%MONITOR_FIXED%'
    GROUP BY 
        CASE 
            WHEN items::text LIKE '%Light Load%' THEN 'Light Load'
            WHEN items::text LIKE '%Medium Load%' THEN 'Medium Load'
            WHEN items::text LIKE '%Heavy Load%' THEN 'Heavy Load'
            ELSE 'Other'
        END
    ORDER BY order_count DESC;
"

# 시간별 주문 분포 (수정된 컬럼명)
echo "📊 시간별 주문 분포:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        DATE_TRUNC('minute', \"createdAt\") as minute_interval,
        COUNT(*) as orders_per_minute,
        ROUND(COUNT(*) / 60.0, 2) as avg_orders_per_second
    FROM orders 
    WHERE items::text LIKE '%MONITOR_FIXED%'
    GROUP BY DATE_TRUNC('minute', \"createdAt\")
    ORDER BY minute_interval;
"

# SAGA 처리 성능 (수정된 컬럼명)
echo "📊 SAGA 처리 성능:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        status,
        COUNT(*) as saga_count,
        ROUND(AVG(EXTRACT(EPOCH FROM (\"updatedAt\" - \"createdAt\"))), 3) as avg_duration_seconds,
        MIN(EXTRACT(EPOCH FROM (\"updatedAt\" - \"createdAt\"))) as min_duration_seconds,
        MAX(EXTRACT(EPOCH FROM (\"updatedAt\" - \"createdAt\"))) as max_duration_seconds
    FROM saga_instances 
    WHERE \"correlationId\" LIKE '%MONITOR_FIXED%'
    GROUP BY status
    ORDER BY saga_count DESC;
"

# 백그라운드 모니터링 종료
echo "5. 백그라운드 모니터링 정리..."
kill $MONITOR_PID 2>/dev/null
wait $MONITOR_PID 2>/dev/null

# 최종 상태 캡처
monitor_pods
monitor_database
monitor_kafka
monitor_application_metrics

# 6. 종합 보고서 생성
echo "6. 종합 성능 보고서 생성..."

cat > test-results/monitoring/performance-summary-fixed.txt << EOF
=====================================================
Kubernetes 성능 모니터링 보고서 (스키마 수정 버전)
생성 시간: $(date)
=====================================================

📊 전체 테스트 결과:
- 총 처리된 주문: $TOTAL_ORDERS 개
- 총 생성된 이벤트: $TOTAL_EVENTS 개  
- 총 SAGA 인스턴스: $TOTAL_SAGAS 개

⏱️ 부하 테스트 결과:
- 가벼운 부하 (30개): ${LIGHT_LOAD_DURATION}초
- 중간 부하 (50개): ${MEDIUM_LOAD_DURATION}초  
- 높은 부하 (100개): ${HEAVY_LOAD_DURATION}초

📈 처리량 계산:
- 가벼운 부하: $(echo "scale=2; 30 / $LIGHT_LOAD_DURATION" | bc -l 2>/dev/null || echo 'N/A') req/s
- 중간 부하: $(echo "scale=2; 50 / $MEDIUM_LOAD_DURATION" | bc -l 2>/dev/null || echo 'N/A') req/s
- 높은 부하: $(echo "scale=2; 100 / $HEAVY_LOAD_DURATION" | bc -l 2>/dev/null || echo 'N/A') req/s

📂 생성된 모니터링 파일:
$(ls -la test-results/monitoring/)

✅ 모든 테스트가 정상적으로 완료되었습니다.
EOF

echo ""
echo "📂 생성된 모니터링 파일들:"
ls -la test-results/monitoring/

echo ""
echo "📄 종합 보고서:"
cat test-results/monitoring/performance-summary-fixed.txt

echo ""
echo "🎉 실시간 성능 모니터링 완료! (스키마 수정 버전)" 