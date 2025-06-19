#!/bin/bash

# 🚀 Kubernetes 환경 완전한 테스트 스위트
# 모든 테스트를 순서대로 실행하여 시스템 안정성과 성능을 검증

echo "🚀 Kubernetes 환경 완전한 테스트 스위트 시작"
echo "=================================================="
echo "📋 테스트 순서:"
echo "   1️⃣ 중복 주문 방지 테스트"
echo "   2️⃣ 확장된 부하 테스트"
echo "   3️⃣ SAGA 패턴 분석"
echo "   4️⃣ 데이터베이스 모니터링"
echo "   5️⃣ 실시간 성능 모니터링"
echo ""

# 결과 저장 디렉토리 생성
mkdir -p test-results/complete-suite
TEST_START_TIME=$(date +%s)

# 포트 포워딩 확인
echo "0️⃣ 사전 확인..."
if ! curl -s http://localhost:3000/health > /dev/null; then
    echo "❌ 포트 포워딩이 활성화되지 않았습니다."
    echo "다음 명령어를 실행해주세요: kubectl port-forward service/nestjs-loadbalancer 3000:3000 -n nestjs-cqrs-saga"
    exit 1
fi

# Pod 상태 확인
echo "📦 Pod 상태 확인:"
kubectl get pods -n nestjs-cqrs-saga
echo ""

# 데이터베이스 초기 상태
POSTGRES_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=postgres -o jsonpath='{.items[0].metadata.name}')
echo "📊 초기 데이터베이스 상태:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        'Initial State' as status,
        (SELECT COUNT(*) FROM orders) as total_orders,
        (SELECT COUNT(*) FROM event_store) as total_events,
        (SELECT COUNT(*) FROM saga_instances) as total_sagas,
        (SELECT COUNT(*) FROM payments) as total_payments,
        (SELECT COUNT(*) FROM users) as total_users;
"
echo ""

# 함수: 테스트 진행 상황 표시
show_progress() {
    local current=$1
    local total=$2
    local test_name=$3
    echo "🔄 진행률: [$current/$total] $test_name"
}

# 함수: 테스트 결과 수집
collect_test_result() {
    local test_name=$1
    local exit_code=$2
    local duration=$3
    
    if [ $exit_code -eq 0 ]; then
        echo "✅ $test_name 완료 (${duration}초)"
        echo "$test_name: SUCCESS (${duration}s)" >> test-results/complete-suite/test-summary.txt
    else
        echo "❌ $test_name 실패 (${duration}초)"
        echo "$test_name: FAILED (${duration}s)" >> test-results/complete-suite/test-summary.txt
    fi
}

# 테스트 요약 파일 초기화
echo "Kubernetes Complete Test Suite Results" > test-results/complete-suite/test-summary.txt
echo "Started: $(date)" >> test-results/complete-suite/test-summary.txt
echo "========================================" >> test-results/complete-suite/test-summary.txt

echo "🎯 테스트 시작!"
echo ""

# 1️⃣ 중복 주문 방지 테스트
show_progress 1 5 "중복 주문 방지 테스트"
TEST1_START=$(date +%s)
./k8s-duplicate-order-test.sh > test-results/complete-suite/01-duplicate-order.log 2>&1
TEST1_EXIT=$?
TEST1_END=$(date +%s)
TEST1_DURATION=$((TEST1_END - TEST1_START))
collect_test_result "중복 주문 방지 테스트" $TEST1_EXIT $TEST1_DURATION

echo "⏳ 시스템 안정화 대기 (10초)..."
sleep 10

# 2️⃣ 확장된 부하 테스트
show_progress 2 5 "확장된 부하 테스트"
TEST2_START=$(date +%s)
./k8s-extended-load-test.sh > test-results/complete-suite/02-extended-load.log 2>&1
TEST2_EXIT=$?
TEST2_END=$(date +%s)
TEST2_DURATION=$((TEST2_END - TEST2_START))
collect_test_result "확장된 부하 테스트" $TEST2_EXIT $TEST2_DURATION

echo "⏳ 시스템 안정화 대기 (15초)..."
sleep 15

# 3️⃣ SAGA 패턴 분석
show_progress 3 5 "SAGA 패턴 분석"
TEST3_START=$(date +%s)
./k8s-saga-analysis.sh > test-results/complete-suite/03-saga-analysis.log 2>&1
TEST3_EXIT=$?
TEST3_END=$(date +%s)
TEST3_DURATION=$((TEST3_END - TEST3_START))
collect_test_result "SAGA 패턴 분석" $TEST3_EXIT $TEST3_DURATION

echo "⏳ 시스템 안정화 대기 (10초)..."
sleep 10

# 4️⃣ 데이터베이스 모니터링
show_progress 4 5 "데이터베이스 모니터링"
TEST4_START=$(date +%s)
./k8s-db-monitoring-test.sh > test-results/complete-suite/04-db-monitoring.log 2>&1
TEST4_EXIT=$?
TEST4_END=$(date +%s)
TEST4_DURATION=$((TEST4_END - TEST4_START))
collect_test_result "데이터베이스 모니터링" $TEST4_EXIT $TEST4_DURATION

echo "⏳ 시스템 안정화 대기 (15초)..."
sleep 15

# 5️⃣ 실시간 성능 모니터링
show_progress 5 5 "실시간 성능 모니터링"
TEST5_START=$(date +%s)
./k8s-performance-monitoring.sh > test-results/complete-suite/05-performance-monitoring.log 2>&1
TEST5_EXIT=$?
TEST5_END=$(date +%s)
TEST5_DURATION=$((TEST5_END - TEST5_START))
collect_test_result "실시간 성능 모니터링" $TEST5_EXIT $TEST5_DURATION

# 전체 테스트 소요 시간 계산
TEST_END_TIME=$(date +%s)
TOTAL_DURATION=$((TEST_END_TIME - TEST_START_TIME))

# 최종 시스템 상태
echo ""
echo "📊 최종 시스템 상태:"
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
    SELECT 
        'Final State' as status,
        (SELECT COUNT(*) FROM orders) as total_orders,
        (SELECT COUNT(*) FROM event_store) as total_events,
        (SELECT COUNT(*) FROM saga_instances) as total_sagas,
        (SELECT COUNT(*) FROM payments) as total_payments,
        (SELECT COUNT(*) FROM users) as total_users;
"

echo ""
echo "📦 최종 Pod 상태:"
kubectl get pods -n nestjs-cqrs-saga

# 성공/실패 카운트
SUCCESS_COUNT=$(grep "SUCCESS" test-results/complete-suite/test-summary.txt | wc -l | tr -d ' ')
FAILED_COUNT=$(grep "FAILED" test-results/complete-suite/test-summary.txt | wc -l | tr -d ' ')

# 최종 보고서 생성
echo "" >> test-results/complete-suite/test-summary.txt
echo "========================================" >> test-results/complete-suite/test-summary.txt
echo "Completed: $(date)" >> test-results/complete-suite/test-summary.txt
echo "Total Duration: ${TOTAL_DURATION} seconds" >> test-results/complete-suite/test-summary.txt
echo "Successful Tests: $SUCCESS_COUNT" >> test-results/complete-suite/test-summary.txt
echo "Failed Tests: $FAILED_COUNT" >> test-results/complete-suite/test-summary.txt

# 결과 요약 출력
echo ""
echo "🎉 완전한 테스트 스위트 완료!"
echo "=================================="
echo "⏱️  총 소요시간: ${TOTAL_DURATION}초 ($(echo "scale=1; $TOTAL_DURATION / 60" | bc -l)분)"
echo "✅ 성공한 테스트: $SUCCESS_COUNT개"
echo "❌ 실패한 테스트: $FAILED_COUNT개"
echo ""

# 각 테스트별 소요시간
echo "📋 테스트별 소요시간:"
echo "  1️⃣ 중복 주문 방지: ${TEST1_DURATION}초"
echo "  2️⃣ 확장된 부하: ${TEST2_DURATION}초"
echo "  3️⃣ SAGA 분석: ${TEST3_DURATION}초"
echo "  4️⃣ DB 모니터링: ${TEST4_DURATION}초"
echo "  5️⃣ 성능 모니터링: ${TEST5_DURATION}초"
echo ""

# 결과 파일들
echo "📂 생성된 결과 파일들:"
ls -la test-results/complete-suite/
echo ""

echo "📄 테스트 요약:"
cat test-results/complete-suite/test-summary.txt
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
    echo "🎊 모든 테스트가 성공적으로 완료되었습니다!"
    echo "✨ 시스템이 프로덕션 환경에서 사용할 준비가 되었습니다."
else
    echo "⚠️  일부 테스트가 실패했습니다. 로그 파일을 확인해주세요:"
    echo "   📁 test-results/complete-suite/ 디렉토리를 확인하세요"
fi

echo ""
echo "🏁 테스트 스위트 종료" 