#!/bin/bash

# 🎯 NestJS CQRS SAGA 시스템 완전 테스트 수트
# 중복 요청 방지 및 다중 노드 환경 검증

echo "🚀 CQRS SAGA 시스템 완전 테스트 수트"
echo "===================================="
echo "시작 시간: $(date)"

# test-results 폴더 초기화
rm -rf test-results
mkdir -p test-results

# 🔧 사전 확인
echo "📋 사전 확인 진행 중..."

# Multi-node 환경 확인
if ! docker ps | grep "nestjs-cqrs-saga-nginx-1" > /dev/null; then
    echo "❌ Multi-node 환경이 실행되지 않았습니다"
    echo "docker-compose up --build -d 를 실행하세요"
    exit 1
fi

echo "✅ Multi-node 환경 확인됨"

# Health check
if ! curl -s http://localhost:8090/health | jq -e '.status == "ok"' > /dev/null; then
    echo "❌ 애플리케이션이 정상 작동하지 않습니다"
    exit 1
fi

echo "✅ 애플리케이션 Health check 통과"

# 초기 데이터 정리
echo "🧹 초기 데이터 정리 중..."
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "DELETE FROM orders; DELETE FROM event_store; DELETE FROM saga_instances; DELETE FROM payments;" > test-results/initial-cleanup.log
echo "✅ 초기 데이터 정리 완료"

echo ""
echo "📝 테스트 계획:"
echo "1. 중복 요청 Order 생성 테스트 (duplicate-order-test.sh)"
echo "2. 개별 요청 Order 생성 테스트 (individual-order-test.sh)" 
echo "3. 혼합 시나리오 테스트 (mixed-order-test-fixed.sh)"
echo ""

# 🔥 테스트 시작
START_TIME=$(date +%s)

# 1️⃣ 중복 요청 테스트
echo "=== 1️⃣ 중복 요청 테스트 시작 ==="
chmod +x duplicate-order-test.sh
if ./duplicate-order-test.sh; then
    echo "✅ 중복 요청 테스트 성공"
    TEST1_RESULT="SUCCESS"
else
    echo "❌ 중복 요청 테스트 실패"
    TEST1_RESULT="FAILED"
fi
echo ""

# 잠시 대기 (시스템 안정화)
echo "⏳ 시스템 안정화 대기..."
sleep 5

# 2️⃣ 개별 요청 테스트
echo "=== 2️⃣ 개별 요청 테스트 시작 ==="
chmod +x individual-order-test.sh
if ./individual-order-test.sh; then
    echo "✅ 개별 요청 테스트 성공"
    TEST2_RESULT="SUCCESS"
else
    echo "❌ 개별 요청 테스트 실패"
    TEST2_RESULT="FAILED"
fi
echo ""

# 잠시 대기 (시스템 안정화)
echo "⏳ 시스템 안정화 대기..."
sleep 5

# 3️⃣ 혼합 시나리오 테스트
echo "=== 3️⃣ 혼합 시나리오 테스트 시작 ==="
chmod +x mixed-order-test-fixed.sh
if ./mixed-order-test-fixed.sh; then
    echo "✅ 혼합 시나리오 테스트 성공"
    TEST3_RESULT="SUCCESS"
else
    echo "❌ 혼합 시나리오 테스트 실패"
    TEST3_RESULT="FAILED"
fi
echo ""

# 📊 최종 분석
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo "🏁 전체 테스트 수트 완료"
echo "============================"
echo "완료 시간: $(date)"
echo "소요 시간: ${TOTAL_TIME}초"
echo ""

# 최종 결과 요약
echo "📊 테스트 결과 요약:"
echo "  1. 중복 요청 테스트: $TEST1_RESULT"
echo "  2. 개별 요청 테스트: $TEST2_RESULT"
echo "  3. 혼합 시나리오 테스트: $TEST3_RESULT"
echo ""

# 성공/실패 카운트
SUCCESS_COUNT=0
if [ "$TEST1_RESULT" = "SUCCESS" ]; then SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); fi
if [ "$TEST2_RESULT" = "SUCCESS" ]; then SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); fi
if [ "$TEST3_RESULT" = "SUCCESS" ]; then SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); fi

echo "📈 총 통계: $SUCCESS_COUNT/3 성공"

# 데이터베이스 최종 상태
echo ""
echo "🗄️ 최종 데이터베이스 상태:"
FINAL_ORDERS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders;")
FINAL_SAGAS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances;")
FINAL_EVENTS=$(docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM event_store;")

echo "  - 총 주문 수: $FINAL_ORDERS"
echo "  - 총 SAGA 수: $FINAL_SAGAS"  
echo "  - 총 이벤트 수: $FINAL_EVENTS"

# 상세 상태 분포
echo ""
echo "📊 상세 상태 분포:"
docker exec -i nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "
SELECT 
    'Orders' as table_name,
    status,
    COUNT(*) as count
FROM orders 
GROUP BY status
UNION ALL
SELECT 
    'Sagas' as table_name,
    status,
    COUNT(*) as count
FROM saga_instances 
GROUP BY status
ORDER BY table_name, status;
" > test-results/final-status-distribution.txt

cat test-results/final-status-distribution.txt

echo ""
echo "📂 생성된 로그 파일들:"
ls -la test-results/

echo ""
if [ $SUCCESS_COUNT -eq 3 ]; then
    echo "🎉 모든 테스트 성공! CQRS SAGA 시스템이 완벽하게 작동합니다!"
    exit 0
else
    echo "⚠️  일부 테스트 실패. 로그 파일을 확인하세요."
    exit 1
fi 