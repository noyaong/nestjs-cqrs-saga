#!/bin/bash

# 💾 Kubernetes 환경 데이터베이스 성능 모니터링
# 쿼리 성능, 커넥션 풀 상태, 데이터베이스 메트릭 분석

echo "💾 Kubernetes 환경 데이터베이스 성능 모니터링 시작"
echo "================================================"

# 결과 저장 디렉토리 생성
mkdir -p test-results

# 포트 포워딩 확인
echo "0. 포트 포워딩 상태 확인..."
if ! curl -s http://localhost:3000/health > /dev/null; then
    echo "❌ 포트 포워딩이 활성화되지 않았습니다."
    exit 1
fi
echo "✅ 포트 포워딩 확인 완료"

# PostgreSQL Pod 찾기
POSTGRES_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POSTGRES_POD" ]; then
    echo "❌ PostgreSQL Pod를 찾을 수 없습니다"
    exit 1
fi
echo "✅ PostgreSQL Pod 확인: $POSTGRES_POD"

# 1. 데이터베이스 기본 정보 수집
echo "1. 데이터베이스 기본 정보 수집 중..."

echo "=== PostgreSQL 버전 및 설정 ===" | tee test-results/db-basic-info.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT version() as postgresql_version;
" | tee -a test-results/db-basic-info.txt

echo "=== 데이터베이스 크기 ===" | tee -a test-results/db-basic-info.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        pg_database.datname as database_name,
        pg_size_pretty(pg_database_size(pg_database.datname)) as size
    FROM pg_database 
    WHERE datname = 'nestjs_cqrs';
" | tee -a test-results/db-basic-info.txt

echo "=== 테이블별 데이터 크기 ===" | tee -a test-results/db-basic-info.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
        pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - 
                      pg_relation_size(schemaname||'.'||tablename)) as index_size
    FROM pg_tables 
    WHERE schemaname = 'public' 
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
" | tee -a test-results/db-basic-info.txt

# 2. 커넥션 풀 상태 모니터링
echo "2. 커넥션 풀 상태 모니터링..."

echo "=== 현재 활성 커넥션 ===" | tee test-results/db-connections.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        state,
        COUNT(*) as connection_count,
        ROUND(AVG(EXTRACT(EPOCH FROM (now() - backend_start)))) as avg_duration_seconds
    FROM pg_stat_activity 
    WHERE datname = 'nestjs_cqrs'
    GROUP BY state
    ORDER BY connection_count DESC;
" | tee -a test-results/db-connections.txt

echo "=== 커넥션 상세 정보 ===" | tee -a test-results/db-connections.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        pid,
        usename,
        application_name,
        client_addr,
        state,
        EXTRACT(EPOCH FROM (now() - backend_start)) as connection_age_seconds,
        EXTRACT(EPOCH FROM (now() - state_change)) as state_age_seconds
    FROM pg_stat_activity 
    WHERE datname = 'nestjs_cqrs'
    ORDER BY backend_start DESC
    LIMIT 10;
" | tee -a test-results/db-connections.txt

# 3. 쿼리 성능 분석
echo "3. 쿼리 성능 분석..."

echo "=== 테이블별 통계 ===" | tee test-results/db-query-performance.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        relname as table_name,
        seq_scan,
        seq_tup_read,
        idx_scan,
        idx_tup_fetch,
        n_tup_ins as inserts,
        n_tup_upd as updates,
        n_tup_del as deletes,
        n_live_tup as live_tuples,
        n_dead_tup as dead_tuples
    FROM pg_stat_user_tables 
    ORDER BY seq_tup_read + idx_tup_fetch DESC;
" | tee -a test-results/db-query-performance.txt

echo "=== 인덱스 사용 통계 ===" | tee -a test-results/db-query-performance.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        schemaname,
        tablename,
        indexname,
        idx_scan as index_scans,
        idx_tup_read as tuples_read,
        idx_tup_fetch as tuples_fetched
    FROM pg_stat_user_indexes 
    ORDER BY idx_scan DESC
    LIMIT 10;
" | tee -a test-results/db-query-performance.txt

# 4. 락(Lock) 및 대기 상태 분석  
echo "4. 락 및 대기 상태 분석..."

echo "=== 현재 락 상태 ===" | tee test-results/db-locks.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        mode,
        locktype,
        relation::regclass as table_name,
        pid,
        granted,
        COUNT(*) as lock_count
    FROM pg_locks 
    WHERE database = (SELECT oid FROM pg_database WHERE datname = 'nestjs_cqrs')
    GROUP BY mode, locktype, relation, pid, granted
    ORDER BY lock_count DESC;
" | tee -a test-results/db-locks.txt

echo "=== 대기 중인 쿼리 ===" | tee -a test-results/db-locks.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        pid,
        state,
        wait_event_type,
        wait_event,
        query_start,
        EXTRACT(EPOCH FROM (now() - query_start)) as query_duration_seconds,
        LEFT(query, 100) as query_preview
    FROM pg_stat_activity 
    WHERE datname = 'nestjs_cqrs' 
      AND state != 'idle'
      AND wait_event IS NOT NULL
    ORDER BY query_start ASC;
" | tee -a test-results/db-locks.txt

# 5. 데이터베이스 성능 부하 테스트
echo "5. 데이터베이스 성능 부하 테스트..."

# 테스트 사용자 생성
TEST_EMAIL="k8s-db-test-$(date +%s)@example.com"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"testpass123\", \"firstName\": \"DB\", \"lastName\": \"Test\"}")

TOKEN=$(echo $REGISTER_RESPONSE | jq -r '.accessToken')
if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 토큰 획득 실패"
    exit 1
fi

# 동시 쿼리 부하 테스트
echo "동시 데이터베이스 쿼리 부하 테스트 (50개 요청)..."
DB_LOAD_START_TIME=$(date +%s%N)

for i in {1..50}; do
    {
        curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"DB_TEST_${i}_$(date +%s)\",
              \"productName\": \"DB Load Test Product $i\",
              \"quantity\": 1,
              \"price\": 1500
            }],
            \"shippingAddress\": \"DB Test Address $i\"
          }" > /dev/null
    } &
done

wait
DB_LOAD_END_TIME=$(date +%s%N)
DB_LOAD_DURATION=$(( ($DB_LOAD_END_TIME - $DB_LOAD_START_TIME) / 1000000 ))

echo "데이터베이스 부하 테스트 완료: ${DB_LOAD_DURATION}ms"

# 부하 테스트 후 성능 메트릭 수집
sleep 5
echo "=== 부하 테스트 후 커넥션 상태 ===" | tee test-results/db-load-test-result.txt
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        state,
        COUNT(*) as connection_count
    FROM pg_stat_activity 
    WHERE datname = 'nestjs_cqrs'
    GROUP BY state;
" | tee -a test-results/db-load-test-result.txt

# 6. 실시간 성능 모니터링 (10초간)
echo "6. 실시간 성능 모니터링 (10초간)..."

MONITOR_START_TIME=$(date +%s)
echo "=== 실시간 데이터베이스 활동 ===" | tee test-results/db-realtime-monitoring.txt

for i in {1..10}; do
    echo "--- $(date) (${i}/10) ---" | tee -a test-results/db-realtime-monitoring.txt
    
    # 현재 활성 쿼리 수
    ACTIVE_QUERIES=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
        SELECT COUNT(*) FROM pg_stat_activity 
        WHERE datname = 'nestjs_cqrs' AND state = 'active';
    " | tr -d ' ')
    
    # TPS (대략적)
    CURRENT_COMMITS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
        SELECT xact_commit FROM pg_stat_database WHERE datname = 'nestjs_cqrs';
    " | tr -d ' ')
    
    echo "활성 쿼리: $ACTIVE_QUERIES, 총 커밋: $CURRENT_COMMITS" | tee -a test-results/db-realtime-monitoring.txt
    
    sleep 1
done

# 7. 전체 결과 요약
echo "7. 데이터베이스 성능 분석 결과 요약..."
echo "====================================="

# 최종 통계 수집
TOTAL_ORDERS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT COUNT(*) FROM orders;
" | tr -d ' ')

TOTAL_EVENTS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT COUNT(*) FROM event_store;
" | tr -d ' ')

TOTAL_SAGAS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT COUNT(*) FROM saga_instances;
" | tr -d ' ')

DB_SIZE=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "
    SELECT pg_size_pretty(pg_database_size('nestjs_cqrs'));
" | tr -d ' ')

echo "📊 최종 데이터베이스 통계:"
echo "  - 데이터베이스 크기: $DB_SIZE"
echo "  - 총 주문 수: $TOTAL_ORDERS"
echo "  - 총 이벤트 수: $TOTAL_EVENTS"
echo "  - 총 SAGA 수: $TOTAL_SAGAS"
echo "  - 부하 테스트 시간: ${DB_LOAD_DURATION}ms"

# 추가 성능 메트릭
echo "📈 성능 지표:"
echo "  - 평균 주문당 이벤트: $(echo "scale=2; $TOTAL_EVENTS / $TOTAL_ORDERS" | bc -l 2>/dev/null || echo "계산불가")"
echo "  - 부하 테스트 처리량: $(echo "scale=2; 50000 / $DB_LOAD_DURATION" | bc -l 2>/dev/null || echo "계산불가") req/sec"

echo ""
echo "📂 생성된 모니터링 파일들:"
ls -la test-results/db-*

echo ""
echo "🎉 데이터베이스 성능 모니터링 완료!" 