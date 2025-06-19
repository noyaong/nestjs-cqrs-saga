#!/bin/bash

# 📈 Kubernetes 환경 확장된 부하 테스트
# 100개, 200개, 500개 동시 요청으로 시스템 한계 테스트

echo "📈 Kubernetes 환경 확장된 부하 테스트 시작"
echo "============================================"

# 결과 저장 디렉토리 생성
mkdir -p test-results

# 포트 포워딩 확인
echo "0. 포트 포워딩 상태 확인..."
if ! curl -s http://localhost:3000/health > /dev/null; then
    echo "❌ 포트 포워딩이 활성화되지 않았습니다."
    echo "다음 명령어를 실행하세요: kubectl port-forward service/nestjs-loadbalancer 3000:3000 -n nestjs-cqrs-saga"
    exit 1
fi
echo "✅ 포트 포워딩 확인 완료"

# 테스트 사용자 생성
echo "1. 테스트 계정 생성 중..."
TEST_EMAIL="k8s-load-test-$(date +%s)@example.com"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"testpass123\", \"firstName\": \"Load\", \"lastName\": \"Test\"}")

TOKEN=$(echo $REGISTER_RESPONSE | jq -r '.accessToken')
if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 토큰 획득 실패"
    exit 1
fi
echo "✅ 토큰 획득 성공"

# 초기 시스템 상태 확인
echo "2. 초기 시스템 상태 확인..."
echo "=== Pod 리소스 사용량 ===" | tee test-results/k8s-load-test-initial-status.txt
kubectl top pods -n nestjs-cqrs-saga 2>/dev/null | tee -a test-results/k8s-load-test-initial-status.txt || echo "metrics-server 없음" | tee -a test-results/k8s-load-test-initial-status.txt

# 부하 테스트 함수
run_load_test() {
    local REQUESTS=$1
    local TEST_NAME=$2
    local BATCH_SIZE=10
    
    echo ""
    echo "🔥 $TEST_NAME: $REQUESTS개 요청 시작..."
    
    START_TIME=$(date +%s%N)
    SUCCESS_COUNT=0
    ERROR_COUNT=0
    
    # 배치 단위로 요청 실행
    for ((batch=0; batch<REQUESTS; batch+=BATCH_SIZE)); do
        current_batch_size=$((REQUESTS - batch < BATCH_SIZE ? REQUESTS - batch : BATCH_SIZE))
        
        for ((i=0; i<current_batch_size; i++)); do
            request_id=$((batch + i + 1))
            {
                RESPONSE=$(curl -s -w "%{http_code}" -X POST http://localhost:3000/orders \
                  -H "Content-Type: application/json" \
                  -H "Authorization: Bearer $TOKEN" \
                  -d "{
                    \"items\": [{
                      \"productId\": \"LOAD_TEST_${REQUESTS}_${request_id}\",
                      \"productName\": \"Load Test $REQUESTS Product $request_id\",
                      \"quantity\": 1,
                      \"price\": 1000
                    }],
                    \"shippingAddress\": \"Load Test Address\"
                  }")
                
                HTTP_CODE="${RESPONSE: -3}"
                if [ "$HTTP_CODE" = "201" ]; then
                    echo "SUCCESS" > /tmp/load_result_${REQUESTS}_${request_id}
                else
                    echo "ERROR_$HTTP_CODE" > /tmp/load_result_${REQUESTS}_${request_id}
                fi
            } &
        done
        
        # 배치 간 짧은 대기 (시스템 과부하 방지)
        sleep 0.05
    done
    
    wait
    END_TIME=$(date +%s%N)
    
    # 결과 집계
    for ((i=1; i<=REQUESTS; i++)); do
        if [ -f "/tmp/load_result_${REQUESTS}_${i}" ]; then
            RESULT=$(cat /tmp/load_result_${REQUESTS}_${i})
            if [ "$RESULT" = "SUCCESS" ]; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                ERROR_COUNT=$((ERROR_COUNT + 1))
            fi
            rm -f /tmp/load_result_${REQUESTS}_${i}
        fi
    done
    
    DURATION=$(( ($END_TIME - $START_TIME) / 1000000 ))
    THROUGHPUT=$(echo "scale=2; $SUCCESS_COUNT * 1000 / $DURATION" | bc -l 2>/dev/null || echo "계산불가")
    
    echo "  📊 $TEST_NAME 결과:"
    echo "    - 성공: $SUCCESS_COUNT"
    echo "    - 실패: $ERROR_COUNT"
    echo "    - 총 시간: ${DURATION}ms"
    echo "    - 처리량: ${THROUGHPUT} req/sec"
    echo "    - 평균 응답시간: $(echo "scale=2; $DURATION / $REQUESTS" | bc -l)ms"
    
    # 결과를 파일에 저장
    echo "$TEST_NAME,$REQUESTS,$SUCCESS_COUNT,$ERROR_COUNT,$DURATION,$THROUGHPUT" >> test-results/k8s-load-test-results.csv
}

# CSV 헤더 생성
echo "TestName,Requests,Success,Error,Duration_ms,Throughput_rps" > test-results/k8s-load-test-results.csv

# 3. 점진적 부하 테스트
echo "3. 점진적 부하 테스트 시작..."

# 100개 요청 테스트
run_load_test 100 "중간부하테스트"

# 시스템 안정화 대기
echo "⏳ 시스템 안정화 대기 (10초)..."
sleep 10

# 200개 요청 테스트
run_load_test 200 "고부하테스트"

# 시스템 안정화 대기
echo "⏳ 시스템 안정화 대기 (15초)..."
sleep 15

# 500개 요청 테스트 (극한 테스트)
run_load_test 500 "극한부하테스트"

echo ""
echo "4. 최종 시스템 상태 확인..."
echo "=== Pod 리소스 사용량 (테스트 후) ===" | tee test-results/k8s-load-test-final-status.txt
kubectl top pods -n nestjs-cqrs-saga 2>/dev/null | tee -a test-results/k8s-load-test-final-status.txt || echo "metrics-server 없음" | tee -a test-results/k8s-load-test-final-status.txt

echo "=== Pod 상태 ===" | tee -a test-results/k8s-load-test-final-status.txt
kubectl get pods -n nestjs-cqrs-saga | tee -a test-results/k8s-load-test-final-status.txt

# 데이터베이스 최종 상태
POSTGRES_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POSTGRES_POD" ]; then
    echo "=== 데이터베이스 통계 ===" | tee -a test-results/k8s-load-test-final-status.txt
    TOTAL_ORDERS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders;" | tr -d ' ')
    TOTAL_SAGAS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances;" | tr -d ' ')
    TOTAL_EVENTS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM event_store;" | tr -d ' ')
    
    echo "  - 총 주문 수: $TOTAL_ORDERS" | tee -a test-results/k8s-load-test-final-status.txt
    echo "  - 총 SAGA 수: $TOTAL_SAGAS" | tee -a test-results/k8s-load-test-final-status.txt
    echo "  - 총 이벤트 수: $TOTAL_EVENTS" | tee -a test-results/k8s-load-test-final-status.txt
fi

echo ""
echo "📊 확장된 부하 테스트 결과 요약:"
echo "================================="
cat test-results/k8s-load-test-results.csv | column -t -s','

echo ""
echo "📂 생성된 결과 파일들:"
ls -la test-results/k8s-load-test-*

echo ""
echo "🎉 확장된 부하 테스트 완료!" 