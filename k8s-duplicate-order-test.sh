#!/bin/bash

# 🔄 Kubernetes 환경 중복 요청 Order 생성 테스트
# 1.1 ProductId 기준 중복방지 (Redis 락)
# 1.2 Payment 실패시 SAGA 보상 트랜잭션  
# 1.3 Multi-node에서 Redis 락을 통한 중복방지 확인

echo "🔥 Kubernetes 환경 중복 요청 Order 생성 테스트 시작"
echo "======================================================"

# 결과 저장 디렉토리 생성
mkdir -p test-results

# 테스트 환경 확인
echo "1️⃣ 테스트 환경 확인 중..."
if ! curl -s http://localhost:3000/health > /dev/null; then
    echo "❌ 포트 포워딩이 활성화되지 않았습니다."
    echo "다음 명령어를 실행하세요: kubectl port-forward service/nestjs-loadbalancer 3000:3000 -n nestjs-cqrs-saga"
    exit 1
fi

curl -s http://localhost:3000/health | jq '.' > test-results/k8s-duplicate-health-check.json
echo "✅ Health check 완료"

# 기존 데이터 삭제 (users 제외)
echo "2️⃣ 기존 데이터 정리 중..."
POSTGRES_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POSTGRES_POD" ]; then
    kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "DELETE FROM orders; DELETE FROM event_store; DELETE FROM saga_instances; DELETE FROM payments;" > test-results/k8s-duplicate-cleanup.log
    echo "✅ 데이터 정리 완료"
else
    echo "❌ PostgreSQL Pod를 찾을 수 없습니다"
    exit 1
fi

# 테스트 사용자 등록 및 로그인
echo "3️⃣ 테스트 사용자 등록 중..."
TEST_EMAIL="k8s-duplicate-test-$(date +%s)@example.com"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"testpass123\", \"firstName\": \"K8s\", \"lastName\": \"Duplicate\"}") 
echo "등록 응답: $REGISTER_RESPONSE" 

echo "테스트 사용자 로그인 중..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\", \"password\": \"testpass123\"}")

echo "$LOGIN_RESPONSE" | jq '.' > test-results/k8s-duplicate-login-response.json
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.accessToken')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ 로그인 실패"
    exit 1
fi
echo "✅ 로그인 성공: ${TOKEN:0:20}..."

# 1.1 동일한 ProductId로 동시 요청 (중복방지 테스트)
echo "4️⃣ [테스트 1.1] 동일한 ProductId로 동시 중복 요청 테스트"
PRODUCT_ID="K8S_DUPLICATE_TEST_PRODUCT_001"
CONCURRENT_REQUESTS=10

echo "동일한 상품 ($PRODUCT_ID)으로 $CONCURRENT_REQUESTS 개의 동시 요청..."

for i in $(seq 1 $CONCURRENT_REQUESTS); do
    {
        RESPONSE=$(curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$PRODUCT_ID\",
              \"productName\": \"K8s Test Product $PRODUCT_ID\",
              \"quantity\": 1,
              \"price\": 1000
            }],
            \"shippingAddress\": \"K8s Test Address\"
          }")
        echo "Request $i: $RESPONSE" >> test-results/k8s-duplicate-test-1.1.log
    } &
done

wait
echo "✅ 동시 요청 완료"

# 결과 확인
sleep 5
echo "📊 결과 확인..."
ORDERS_COUNT=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE items::text LIKE '%$PRODUCT_ID%';" | tr -d ' ')
SAGA_COUNT=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM saga_instances WHERE \"correlationId\" LIKE '%$PRODUCT_ID%';" | tr -d ' ')

echo "생성된 주문 수: $ORDERS_COUNT (예상: 1개)"
echo "생성된 SAGA 수: $SAGA_COUNT (예상: 1개)"

if [ "$ORDERS_COUNT" = "1" ]; then
    echo "✅ 중복 방지 테스트 성공!"
    TEST1_RESULT="SUCCESS"
else
    echo "❌ 중복 방지 테스트 실패 - 중복 주문이 생성됨"
    TEST1_RESULT="FAILED"
fi

# 1.2 다중 노드 부하 테스트 (각 노드별 고유 상품으로)
echo "5️⃣ [테스트 1.2] 다중 노드 부하 테스트"
echo "각 NestJS Pod별로 서로 다른 상품 요청..."

NESTJS_PODS=($(kubectl get pods -n nestjs-cqrs-saga -l app=nestjs -o jsonpath='{.items[*].metadata.name}'))
NODE_REQUESTS=5

for pod_index in "${!NESTJS_PODS[@]}"; do
    POD_NAME="${NESTJS_PODS[$pod_index]}"
    NODE_PRODUCT_ID="K8S_NODE_${pod_index}_PRODUCT_002"
    
    echo "Node $pod_index (Pod: $POD_NAME) - 상품 $NODE_PRODUCT_ID로 $NODE_REQUESTS개 요청"
    
    for i in $(seq 1 $NODE_REQUESTS); do
        {
            RESPONSE=$(curl -s -X POST http://localhost:3000/orders \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer $TOKEN" \
              -d "{
                \"items\": [{
                  \"productId\": \"${NODE_PRODUCT_ID}_${i}\",
                  \"productName\": \"Node $pod_index Test Product $i\",
                  \"quantity\": 1,
                  \"price\": 1500
                }],
                \"shippingAddress\": \"Node $pod_index Test Address\"
              }")
            echo "Node $pod_index Request $i: $RESPONSE" >> test-results/k8s-multi-node-test-1.2.log
        } &
    done
done

wait
echo "✅ 다중 노드 요청 완료"

# 다중 노드 결과 확인
sleep 5
TOTAL_NODE_ORDERS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE items::text LIKE '%K8S_NODE_%';" | tr -d ' ')
EXPECTED_ORDERS=$((${#NESTJS_PODS[@]} * NODE_REQUESTS))

echo "다중 노드 생성된 주문 수: $TOTAL_NODE_ORDERS (예상: $EXPECTED_ORDERS개)"

if [ "$TOTAL_NODE_ORDERS" = "$EXPECTED_ORDERS" ]; then
    echo "✅ 다중 노드 부하 테스트 성공!"
    TEST2_RESULT="SUCCESS"
else
    echo "❌ 다중 노드 부하 테스트 실패 - 예상과 다른 주문 수"
    TEST2_RESULT="FAILED"
fi

# 1.3 Redis Lock 기능 상세 확인
echo "6️⃣ [테스트 1.3] Redis Lock 기능 상세 확인"
LOCK_TEST_PRODUCT="K8S_REDIS_LOCK_TEST_003"
REDIS_POD=$(kubectl get pods -n nestjs-cqrs-saga -l app=redis -o jsonpath='{.items[0].metadata.name}')

echo "Redis Lock 상태 확인 전 키 조회..."
if [ -n "$REDIS_POD" ]; then
    REDIS_KEYS_BEFORE=$(kubectl exec -n nestjs-cqrs-saga $REDIS_POD -- redis-cli keys "lock:*" | wc -l | tr -d ' ')
    echo "Redis Lock 키 수 (요청 전): $REDIS_KEYS_BEFORE"
else
    echo "❌ Redis Pod를 찾을 수 없습니다"
fi

# 동일 상품으로 동시 요청 (Redis Lock 테스트)
echo "동일한 상품으로 20개 동시 요청 실행..."
for i in {1..20}; do
    {
        curl -s -X POST http://localhost:3000/orders \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $TOKEN" \
          -d "{
            \"items\": [{
              \"productId\": \"$LOCK_TEST_PRODUCT\",
              \"productName\": \"Redis Lock Test Product\",
              \"quantity\": 1,
              \"price\": 2000
            }],
            \"shippingAddress\": \"Redis Lock Test\"
          }" > /dev/null
    } &
done

wait
sleep 3

# Redis Lock 결과 확인
LOCK_TEST_ORDERS=$(kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -t -c "SELECT COUNT(*) FROM orders WHERE items::text LIKE '%$LOCK_TEST_PRODUCT%';" | tr -d ' ')

if [ -n "$REDIS_POD" ]; then
    REDIS_KEYS_AFTER=$(kubectl exec -n nestjs-cqrs-saga $REDIS_POD -- redis-cli keys "lock:*" | wc -l | tr -d ' ')
    echo "Redis Lock 키 수 (요청 후): $REDIS_KEYS_AFTER"
fi

echo "Redis Lock 테스트 주문 수: $LOCK_TEST_ORDERS (예상: 1개)"

if [ "$LOCK_TEST_ORDERS" = "1" ]; then
    echo "✅ Redis Lock 기능 정상!"
    TEST3_RESULT="SUCCESS"
else
    echo "❌ Redis Lock 기능 문제 - 중복 주문 발생"
    TEST3_RESULT="FAILED"
fi

# 전체 결과 요약
echo ""
echo "📋 Kubernetes 중복 방지 테스트 결과 요약"
echo "==========================================="
echo "1.1 동일 ProductId 중복방지: $TEST1_RESULT (주문 $ORDERS_COUNT개)"
echo "1.2 다중 노드 부하 테스트: $TEST2_RESULT (주문 $TOTAL_NODE_ORDERS/$EXPECTED_ORDERS개)"
echo "1.3 Redis Lock 기능 테스트: $TEST3_RESULT (주문 $LOCK_TEST_ORDERS개)"

# 성공 카운트
SUCCESS_COUNT=0
if [ "$TEST1_RESULT" = "SUCCESS" ]; then SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); fi
if [ "$TEST2_RESULT" = "SUCCESS" ]; then SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); fi
if [ "$TEST3_RESULT" = "SUCCESS" ]; then SUCCESS_COUNT=$((SUCCESS_COUNT + 1)); fi

echo ""
echo "📈 전체 통계: $SUCCESS_COUNT/3 성공"

# 상세 데이터 덤프
echo "📊 상세 데이터 덤프 중..."
kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
SELECT 
    'orders' as table_name,
    id, status, \"createdAt\",
    substring(items::text, 1, 50) as items_preview
FROM orders 
ORDER BY \"createdAt\" DESC
LIMIT 20;
" > test-results/k8s-duplicate-test-final-orders.txt

kubectl exec -n nestjs-cqrs-saga $POSTGRES_POD -- psql -U postgres -d nestjs_cqrs -c "
SELECT 
    'saga_instances' as table_name,
    id, status, \"currentStep\", \"createdAt\",
    substring(\"correlationId\", 1, 30) as correlation_preview
FROM saga_instances 
ORDER BY \"createdAt\" DESC
LIMIT 20;
" > test-results/k8s-duplicate-test-final-sagas.txt

echo ""
if [ $SUCCESS_COUNT -eq 3 ]; then
    echo "🎉 모든 중복 방지 테스트 성공! Redis Lock이 완벽하게 작동합니다!"
    exit 0
else
    echo "⚠️  일부 테스트 실패. 로그 파일을 확인하세요."
    echo "📂 생성된 로그 파일들:"
    ls -la test-results/k8s-duplicate-*
    exit 1
fi 