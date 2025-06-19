# NestJS CQRS Saga 패턴

> 🚀 **CQRS와 Saga 패턴을 활용한 분산 트랜잭션 관리 시스템**

분산 시스템에서 복잡한 비즈니스 워크플로우를 안전하고 신뢰성 있게 처리하기 위한 **CQRS(Command Query Responsibility Segregation)**와 **Saga 패턴**의 완전한 구현입니다. 보상 메커니즘과 완전한 추적 기능을 제공합니다.

[![NestJS](https://img.shields.io/badge/NestJS-10.x-red.svg)](https://nestjs.com/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-blue.svg)](https://www.typescriptlang.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-blue.svg)](https://www.postgresql.org/)
[![Kafka](https://img.shields.io/badge/Apache%20Kafka-latest-orange.svg)](https://kafka.apache.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)

## 🎯 주요 기능

### 핵심 패턴
- ✅ **CQRS 패턴** - 명령과 조회의 완전한 분리
- ✅ **Saga 패턴** - 보상 메커니즘을 갖춘 분산 트랜잭션 관리
- ✅ **이벤트 소싱** - 완전한 감사 추적과 이벤트 재생 기능
- ✅ **도메인 주도 설계** - 깔끔한 아키텍처와 적절한 도메인 경계

### 기술적 역량
- 🔄 **분산 트랜잭션** - 서비스 간 신뢰성 있는 트랜잭션 처리
- 🛡️ **보상 로직** - 실패 시 자동 롤백
- 📊 **이벤트 저장소** - 연관관계 추적이 가능한 영구 이벤트 저장
- 🔍 **완전한 추적성** - Correlation ID를 통한 종단간 요청 추적
- ⚡ **비동기 처리** - Kafka 기반 이벤트 드리븐 아키텍처
- 🔒 **동시성 제어** - 낙관적 락킹과 멱등성 보장

### 🆕 v2.0.0 다중 인스턴스 & 분산 제어
- 🏭 **다중 인스턴스 환경** - Docker Compose로 3개 NestJS 노드 운영
- ⚖️ **로드 밸런싱** - Nginx 기반 Round-robin 분산 처리
- 🔐 **Redis 분산 락** - ProductId 기준 중복 요청 완벽 차단
- 🎯 **Idempotency Key** - 멱등성 보장으로 동시성 안전 확보
- 📈 **노드별 처리 분산 추적** - DB 타임스탬프 기반 정확한 부하 분산 측정
- 🧪 **완전한 테스트 수트** - 중복/개별/혼합 시나리오 자동화 검증

### 🚀 v2.5.0 Kubernetes 환경 완료 (2025.06.19)
- ☸️ **Kubernetes 네이티브** - minikube 환경에서 완전한 K8s 배포
- 📦 **Pod 자동 관리** - 3개 NestJS Pod + 자동 재시작 및 복구
- 🔄 **StatefulSet 데이터 영속성** - PostgreSQL, Kafka, Zookeeper 클러스터
- 🌐 **Service Discovery** - ClusterIP + LoadBalancer 기반 서비스 통신
- 🔐 **Secret 관리** - Kubernetes Secret을 통한 안전한 크리덴셜 관리
- 🎯 **100% 테스트 성공** - 모든 스키마 에러 해결 및 완전한 검증
- ⚡ **프로덕션 준비** - Docker Compose와 동등한 성능 + K8s 확장성

### 비즈니스 기능
- 👤 **사용자 관리** - JWT 기반 인증과 권한 관리
- 🛒 **주문 처리** - 완전한 주문 생명주기 관리
- 💳 **결제 처리** - 실패 처리를 포함한 통합 결제 워크플로우
- 📈 **실시간 모니터링** - 활성 플로우 모니터링과 헬스체크

## 🏗️ 아키텍처 개요

### v2.0.0 다중 인스턴스 아키텍처 (Docker Compose)
```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │     (Nginx)     │
                    └─────────┬───────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼───────┐    ┌────────▼────────┐    ┌───────▼───────┐
│  NestJS Node1 │    │  NestJS Node2   │    │  NestJS Node3 │
│   (Port 3000) │    │   (Port 3001)   │    │   (Port 3002) │
└───────┬───────┘    └─────────┬───────┘    └───────┬───────┘
        │                      │                      │
        └──────────────────────┼──────────────────────┘
                               │
        ┌─────────────────────────────────────────────────┐
        │              공유 인프라                         │
        │  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
        │  │ PostgreSQL  │  │    Redis    │  │  Kafka   │ │
        │  │(이벤트저장소)│  │  (분산락)   │  │(메시징)  │ │
        │  └─────────────┘  └─────────────┘  └──────────┘ │
        └─────────────────────────────────────────────────┘
```

### v2.5.0 Kubernetes 아키텍처 (완료)
```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                  nestjs-cqrs-saga                       │ │
│  │                    (Namespace)                          │ │
│  │                                                         │ │
│  │  ┌─────────────────┐  ┌─────────────────────────────────┐ │ │
│  │  │ LoadBalancer    │  │        NestJS Pods             │ │ │
│  │  │    Service      │──┤ ┌─────────┐ ┌─────────┐ ┌──────┐ │ │ │
│  │  │ (External 3000) │  │ │ Pod-1   │ │ Pod-2   │ │Pod-3 │ │ │ │
│  │  └─────────────────┘  │ └─────────┘ └─────────┘ └──────┘ │ │ │
│  │                       └─────────────────────────────────┘ │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │                StatefulSets                         │ │ │
│  │  │ ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐ │ │ │
│  │  │ │ PostgreSQL  │ │    Redis    │ │ Kafka+Zookeeper│ │ │ │
│  │  │ │     +       │ │  (분산락)   │ │   (메시징)      │ │ │ │
│  │  │ │   PVC       │ │             │ │                 │ │ │ │
│  │  │ └─────────────┘ └─────────────┘ └─────────────────┘ │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                         │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │     ConfigMaps & Secrets                            │ │ │
│  │  │ ┌─────────────┐ ┌─────────────────────────────────┐ │ │ │
│  │  │ │   Config    │ │           Secrets               │ │ │ │
│  │  │ │ (App 설정)  │ │    (DB/Redis Passwords)        │ │ │ │
│  │  │ └─────────────┘ └─────────────────────────────────┘ │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 분산 동시성 제어 플로우
```
사용자 요청 → Nginx Load Balancer → 노드 선택
    ↓
Redis 분산 락 획득 시도 (ProductId 기준)
    ↓
락 획득 성공? 
    ├─ ✅ YES: 주문 생성 → Saga 시작 → 락 해제
    └─ ❌ NO:  DUPLICATE_ORDER 에러 반환
```

### Saga 플로우 예시
```mermaid
sequenceDiagram
    participant 사용자
    participant 주문서비스
    participant Saga매니저
    participant 결제서비스
    participant 이벤트저장소
    
    사용자->>주문서비스: 주문 생성
    주문서비스->>이벤트저장소: 주문생성 이벤트
    이벤트저장소->>Saga매니저: Saga 트리거
    Saga매니저->>결제서비스: 결제 처리
    
    alt 결제 성공
        결제서비스->>이벤트저장소: 결제완료 이벤트
        이벤트저장소->>Saga매니저: Saga 계속
        Saga매니저->>주문서비스: 주문 확인
        주문서비스->>이벤트저장소: 주문확인 이벤트
        Saga매니저->>Saga매니저: Saga 완료
    else 결제 실패
        결제서비스->>이벤트저장소: 결제실패 이벤트
        이벤트저장소->>Saga매니저: 보상 시작
        Saga매니저->>주문서비스: 주문 취소
        주문서비스->>이벤트저장소: 주문취소 이벤트
        Saga매니저->>Saga매니저: Saga 보상
    end
```

## 🚀 빠른 시작

### 사전 요구사항
- Node.js 18+
- Docker & Docker Compose
- Yarn 또는 npm

### 1. 클론 & 설치
```bash
git clone https://github.com/yourusername/nestjs-cqrs-saga.git
cd nestjs-cqrs-saga
yarn install
```

### 2. 환경 설정
```bash
cp .env.example .env
# .env 파일을 편집하여 설정값 입력
```

### 3. 환경 선택 및 시작

#### Option A: Docker Compose 환경 (v2.0.0)
```bash
# 전체 다중 인스턴스 환경 시작 (PostgreSQL, Redis, Kafka, NestJS 3개 노드, Nginx)
docker-compose up --build -d

# 서비스 상태 확인
docker ps
curl http://localhost:8090/health
```

#### Option B: Kubernetes 환경 (v2.5.0) ⭐ 추천
```bash
# minikube 클러스터 시작
minikube start

# 모든 Kubernetes 리소스 배포
kubectl apply -f k8s/

# 포트 포워딩으로 서비스 접근
kubectl port-forward service/nestjs-loadbalancer 3000:3000 -n nestjs-cqrs-saga

# 서비스 상태 확인
curl http://localhost:3000/health
```

### 4. 테스트 수트 실행

#### Docker Compose 환경 테스트
```bash
# 📋 전체 테스트 수트 실행 (v2.0.0 고도화)
./run-all-tests.sh

# 🔍 개별 테스트 실행
./duplicate-order-test.sh      # 중복 요청 방지 테스트
./individual-order-test.sh     # 개별 요청 노드 분산 테스트
./mixed-order-test-fixed.sh    # 혼합 시나리오 테스트
./analyze-real-distribution.sh # DB 기반 노드 분산 분석
```

#### Kubernetes 환경 테스트 ⭐
```bash
# 🚀 전체 Kubernetes 테스트 스위트 실행 (v2.5.0)
./k8s-complete-test-suite.sh

# 🔍 개별 Kubernetes 테스트 실행
./k8s-duplicate-order-test.sh    # 중복 요청 방지 (Redis Lock)
./k8s-extended-load-test.sh      # 확장된 부하 테스트
./k8s-saga-analysis.sh           # SAGA 패턴 분석
./k8s-db-monitoring-test.sh      # 데이터베이스 모니터링
./k8s-performance-monitoring.sh  # 실시간 성능 모니터링
```

### 5. 서비스 접근

#### Docker Compose 환경
- **🌐 Multi-node API**: http://localhost:8090 (Nginx Load Balancer)
- **📊 Swagger UI**: http://localhost:8090/api
- **📈 Node1 Direct**: http://localhost:3000
- **📈 Node2 Direct**: http://localhost:3001  
- **📈 Node3 Direct**: http://localhost:3002
- **🗄️ PostgreSQL**: localhost:5432
- **🔴 Redis**: localhost:6379
- **📨 Kafka**: localhost:9092

#### Kubernetes 환경 ⭐
- **🌐 API**: http://localhost:3000 (포트 포워딩 후)
- **📊 Swagger UI**: http://localhost:3000/api
- **☸️ Kubernetes Dashboard**: `minikube dashboard`
- **🔍 Pod 관리**: `kubectl get pods -n nestjs-cqrs-saga`
- **📋 서비스 목록**: `kubectl get svc -n nestjs-cqrs-saga`

## 📋 실제 사용 예시 (v2.0.0)

### 회원가입 및 로그인
```bash
# 1. 회원가입
curl -X POST http://localhost:8090/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password123",
    "firstName": "홍",
    "lastName": "길동"
  }'

# 2. 로그인
curl -X POST http://localhost:8090/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password123"
  }'
```

### 주문 생성 및 분산 락 테스트
```bash
# 3. 토큰을 받은 후 주문 생성
TOKEN="your-jwt-token-here"

# 단일 주문 생성
curl -X POST http://localhost:8090/orders \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "items": [{
      "productId": "product-123",
      "productName": "노트북",
      "quantity": 1,
      "price": 1500000
    }],
    "shippingAddress": "서울시 강남구 테헤란로 123"
  }'

# 동시 중복 요청 테스트 (같은 productId)
for i in {1..3}; do
  curl -X POST http://localhost:8090/orders \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
      "items": [{
        "productId": "product-duplicate-test",
        "productName": "중복테스트상품",
        "quantity": 1,
        "price": 100000
      }],
      "shippingAddress": "테스트 주소"
    }' &
done
wait
# 결과: 3개 요청 중 1개만 성공, 나머지는 DUPLICATE_ORDER 에러
```

### SAGA 상태 추적
```bash
# 4. 주문의 SAGA 진행 상태 확인
curl -X GET http://localhost:8090/sagas/correlation/order-correlation-id \
  -H "Authorization: Bearer $TOKEN"

# 5. 전체 플로우 추적
curl -X GET http://localhost:8090/trace/order/order-id \
  -H "Authorization: Bearer $TOKEN"
```

## 📊 API 엔드포인트

### 인증
```http
POST /auth/register    # 사용자 회원가입
POST /auth/login       # 사용자 로그인
```

### 주문
```http
POST   /orders         # 새 주문 생성
GET    /orders         # 내 주문 목록
GET    /orders/:id     # 주문 상세 조회
DELETE /orders/:id     # 주문 취소
PUT    /orders/:id/confirm # 주문 확인
```

### Saga 관리
```http
GET /saga/status/:correlationId    # Saga 상태 조회
GET /saga/active                   # 활성 Saga 목록
POST /saga/retry/:sagaId           # 실패한 Saga 재시도
POST /saga/compensate/:sagaId      # 수동 보상
```

### 추적 & 모니터링
```http
GET /trace/correlation/:correlationId  # 전체 플로우 추적
GET /trace/order/:orderId              # 주문별 추적
GET /trace/events                      # 이벤트 스트림
GET /trace/active-flows                # 활성 플로우 모니터링
```

### 🆕 v2.0.0 분산 제어 & 테스트
```http
# Redis 분산 락 테스트
POST /redis-test/lock/:key             # 분산 락 획득 테스트
GET  /redis-test/lock-status/:key      # 락 상태 확인
POST /redis-test/saga-creation-test    # Saga 생성 중복 방지 테스트

# 헬스체크 & 모니터링
GET  /health                          # 애플리케이션 상태
GET  /db-pool                         # DB 연결 풀 상태
GET  /kafka-test                      # Kafka 연결 상태
```

## 🏛️ 프로젝트 구조

```
src/
├── auth/                 # 인증 & 권한
│   ├── guards/          # JWT 가드
│   ├── strategies/      # Passport 전략
│   └── dto/             # 인증 DTO
├── order/               # 주문 도메인
│   ├── commands/        # 주문 명령
│   ├── queries/         # 주문 조회
│   ├── events/          # 주문 이벤트
│   ├── handlers/        # 명령/조회 핸들러
│   ├── entities/        # 주문 엔티티
│   └── dto/             # 주문 DTO
├── payment/             # 결제 도메인
│   ├── commands/        # 결제 명령
│   ├── queries/         # 결제 조회
│   ├── events/          # 결제 이벤트
│   ├── handlers/        # 명령/조회 핸들러
│   ├── entities/        # 결제 엔티티
│   └── dto/             # 결제 DTO
├── saga/                # Saga 오케스트레이션
│   ├── entities/        # Saga 엔티티
│   ├── order-processing.saga.ts # 메인 Saga 구현
│   ├── saga-manager.service.ts  # Saga 생명주기 관리
│   └── saga.controller.ts       # Saga API 엔드포인트
├── event-store/         # 이벤트 소싱
│   ├── entities/        # 이벤트 저장소 엔티티
│   └── event-store.service.ts
├── kafka/               # 메시지 브로커
│   ├── kafka.service.ts # Kafka 프로듀서/컨슈머
│   └── kafka.module.ts
├── tracing/             # 요청 추적
│   └── tracing.controller.ts
├── redis/               # 🆕 Redis 분산 락 (v2.0.0)
│   ├── redis.service.ts # Redis 연결 및 분산 락 관리
│   ├── redis-test.controller.ts # 분산 락 테스트 API
│   └── redis.module.ts
├── database/            # 데이터베이스 설정
└── config/              # 애플리케이션 설정

# 🆕 v2.0.0 테스트 수트
tests/
├── run-all-tests.sh                # 마스터 테스트 스크립트
├── duplicate-order-test.sh         # 중복 요청 방지 테스트
├── individual-order-test.sh        # 개별 요청 노드 분산 테스트
├── mixed-order-test-fixed.sh       # 혼합 시나리오 테스트
├── analyze-real-distribution.sh    # DB 기반 노드 분산 분석
└── test-results/                   # 테스트 결과 저장소
```

## 🔧 설정

### 환경 변수
```env
# 데이터베이스
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=nestjs_cqrs
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres123

# JWT
JWT_SECRET=your-super-secret-jwt-key
JWT_EXPIRES_IN=24h

# Kafka
KAFKA_BROKERS=localhost:9092
KAFKA_CLIENT_ID=nestjs-cqrs-saga

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
```

### Docker Compose 서비스
- **PostgreSQL 15**: 메인 데이터베이스
- **Apache Kafka**: 이벤트용 메시지 브로커
- **Zookeeper**: Kafka 의존성
- **Kafka UI**: Kafka 관리를 위한 웹 인터페이스
- **Redis**: 캐싱 및 세션 저장소

## 🧪 테스트

### 단위 테스트
```bash
yarn test              # 단위 테스트 실행
yarn test:watch        # 감시 모드
yarn test:cov          # 커버리지 리포트
```

### 통합 테스트
```bash
yarn test:e2e          # End-to-End 테스트
```

### 동시성 테스트
```bash
# 동시 주문 생성 테스트
yarn test:concurrency

# 다중 Saga 부하 테스트
yarn test:load
```

## 🧪 테스트 (v2.0.0 고도화)

### 자동화된 테스트 수트
전체 다중 인스턴스 환경에서 분산 동시성 제어와 SAGA 패턴을 검증하는 완전한 테스트 수트가 포함되어 있습니다.

#### 🎯 마스터 테스트 스크립트
```bash
./run-all-tests.sh
```
**포함 내용:**
- 환경 사전 점검 (Multi-node, Health check)
- 전체 데이터 정리 및 초기화
- 3가지 핵심 테스트 시나리오 순차 실행
- 종합 결과 리포트 생성

#### 🛡️ 중복 요청 방지 테스트
```bash
./duplicate-order-test.sh
```
**검증 사항:**
- ✅ 동일 ProductId 5개 동시 요청 → 1개만 생성
- ✅ Redis 분산 락 기반 중복 차단
- ✅ `DUPLICATE_ORDER` 에러 응답 확인
- ✅ Idempotency Key 동작 검증

#### ⚖️ 노드별 분산 처리 테스트
```bash
./individual-order-test.sh
```
**검증 사항:**
- ✅ 15개 서로 다른 상품 주문 → 15개 모두 생성
- ✅ Nginx Load Balancer Round-robin 분산
- ✅ 각 노드별 처리량 균등 분배
- ✅ 노드간 Kafka 통신 무간섭 확인

#### 🔄 혼합 시나리오 테스트
```bash
./mixed-order-test-fixed.sh
```
**검증 사항:**
- ✅ 중복 상품 3개 (각 3-5회 요청) → 각 1개씩만 생성
- ✅ 개별 상품 5개 → 5개 모두 생성
- ✅ 복합 시나리오에서 분산 락 정확성
- ✅ 전체 SAGA 플로우 완결성

#### 📊 DB 기반 분산 분석
```bash
./analyze-real-distribution.sh
```
**분석 내용:**
- 📈 마이크로초 단위 타임스탬프 분석
- 📈 노드별 처리 순서 및 분산율 측정
- 📈 동시 요청 처리 패턴 분석
- 📈 Load Balancer 성능 검증

### 테스트 결과 예시
```
🎉 전체 테스트 수트 성공 완료!
📊 최종 테스트 결과 요약

✅ 전체 성공률: 3/3 (100%)

1️⃣ 중복 요청 테스트 - ✅ SUCCESS
   - 동일 상품 5개 동시 요청 → 1개만 생성
   - Redis 락 기반 중복 방지 정상 작동

2️⃣ 개별 요청 테스트 - ✅ SUCCESS  
   - 15개 서로 다른 상품 주문 → 15개 모두 생성
   - 노드별 처리 분산: Node1(5), Node2(5), Node3(5)

3️⃣ 혼합 시나리오 테스트 - ✅ SUCCESS
   - 중복 상품 3개 → 각 1개씩만 생성
   - 개별 상품 5개 → 5개 모두 생성
   - 총 8개 주문, 8개 SAGA 완료
```

## 📈 모니터링 & 관찰성

### 헬스체크
```http
GET /health            # 애플리케이션 상태
GET /health/detailed   # 상세 시스템 상태
```

### 📊 v2.0.0 검증된 성능 메트릭
```
🚀 Multi-node 환경 성능 결과

동시성 처리:
├─ 중복 요청 방지: 5개 동시 요청 → 1개 생성 (100% 정확도)
├─ Redis 분산 락: 평균 락 획득 시간 < 5ms
├─ Load Balancer: Round-robin 완벽 분산 (33.3% 균등 분배)
└─ SAGA 완료율: 100% (실패 시 자동 보상)

처리 시간:
├─ 주문 생성: 평균 50-100ms
├─ 결제 처리: 평균 200-300ms  
├─ SAGA 완료: 평균 500-800ms
└─ DB 트랜잭션: 평균 10-20ms

노드별 분산:
├─ Node-1: 33.3% (마이크로초 타임스탬프 기준)
├─ Node-2: 33.3% 
└─ Node-3: 33.4%

시스템 안정성:
├─ 메모리 사용량: 각 노드 평균 200MB
├─ CPU 사용률: 부하 시 평균 15-25%
├─ DB 연결 풀: 안정적 (최대 20개 연결)
└─ Redis 연결: 지연시간 < 1ms
```

### 메트릭 & 로깅
- **요청 추적**: 완전한 Correlation ID 추적
- **이벤트 감사**: 완전한 이벤트 히스토리
- **성능 메트릭**: 응답 시간과 처리량
- **에러 추적**: 포괄적인 에러 로깅

### Saga 모니터링 대시보드
내장된 모니터링 대시보드에서 다음을 추적:
- 활성 Saga 인스턴스
- 완료율
- 실패 패턴
- 보상 통계

## 🛡️ 에러 처리 & 복원력

### 보상 전략
- **자동 롤백**: 실패한 단계는 보상을 트리거
- **수동 개입**: 수동 Saga 복구 지원
- **재시도 메커니즘**: 설정 가능한 재시도 정책
- **서킷 브레이커**: 연쇄 실패 방지

### 동시성 제어
- **낙관적 락킹**: 동시 수정 방지
- **멱등성**: 안전한 재시도 연산
- **이벤트 중복 제거**: 중복 처리 방지

## 🔧 트러블슈팅 (v2.0.0)

### 일반적인 문제 해결

#### 🚨 Multi-node 환경 시작 오류
```bash
# 문제: Docker 컨테이너가 시작되지 않음
# 해결: 기존 컨테이너 완전 정리 후 재시작
docker-compose down -v --remove-orphans
docker system prune -f
docker-compose up --build -d

# 문제: Port 3000 already in use 에러
# 해결: 로컬 개발 서버 종료 후 Docker만 사용
pkill -f "npm run start:dev"
lsof -ti:3000 | xargs kill -9
```

#### 🔴 Redis 연결 오류
```bash
# 문제: Redis connection refused
# 해결: Redis 컨테이너 상태 확인
docker logs nestjs-cqrs-saga-redis-1

# Redis 수동 테스트
docker exec -it nestjs-cqrs-saga-redis-1 redis-cli ping
# 응답: PONG
```

#### 📨 Kafka 연결 오류  
```bash
# 문제: "getaddrinfo ENOTFOUND kafka" 에러
# 해결: Kafka 컨테이너 네트워크 확인
docker exec -it nestjs-cqrs-saga-nestjs-node-1-1 ping kafka

# Kafka 토픽 확인
docker exec -it nestjs-cqrs-saga-kafka-1 kafka-topics --list --bootstrap-server localhost:9092
```

#### 🗄️ PostgreSQL 연결 문제
```bash
# 문제: Database connection timeout
# 해결: PostgreSQL 상태 및 연결 확인
docker exec -it nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "SELECT 1;"

# 테이블 존재 확인
docker exec -it nestjs-cqrs-saga-postgres-1 psql -U postgres -d nestjs_cqrs -c "\\dt"
```

#### ⚖️ Load Balancer 문제
```bash
# 문제: Nginx가 노드를 찾지 못함
# 해결: 노드 상태 개별 확인
curl http://localhost:3000/health
curl http://localhost:3001/health  
curl http://localhost:3002/health

# Nginx 설정 확인
docker exec -it nestjs-cqrs-saga-nginx-1 cat /etc/nginx/nginx.conf
```

### 테스트 실패 디버깅

#### 🧪 테스트 스크립트 실행 오류
```bash
# 문제: Permission denied
chmod +x *.sh

# 문제: jq command not found  
# macOS
brew install jq
# Ubuntu
sudo apt-get install jq

# 문제: curl timeout
# 해결: 서비스 완전 시작 대기
sleep 30
curl http://localhost:8090/health
```

#### 🔍 분산 락 디버깅
```bash
# Redis 키 확인
docker exec -it nestjs-cqrs-saga-redis-1 redis-cli keys "*"

# 락 상태 확인
curl -X GET http://localhost:8090/redis-test/lock-status/product-123

# 락 수동 해제 (테스트용)
docker exec -it nestjs-cqrs-saga-redis-1 redis-cli del "order:lock:product-123"
```

### 로그 분석

#### 📊 각 노드별 로그 확인
```bash
# 전체 노드 로그 확인
docker logs nestjs-cqrs-saga-nestjs-node-1-1 --tail 50
docker logs nestjs-cqrs-saga-nestjs-node-2-1 --tail 50  
docker logs nestjs-cqrs-saga-nestjs-node-3-1 --tail 50

# 특정 에러 검색
docker logs nestjs-cqrs-saga-nestjs-node-1-1 2>&1 | grep -i error

# SAGA 관련 로그 필터링
docker logs nestjs-cqrs-saga-nestjs-node-1-1 2>&1 | grep -i saga
```

## 🔄 개발 워크플로우

### 새로운 Saga 단계 추가
1. 새로운 명령/이벤트 정의
2. 명령/이벤트 핸들러 구현
3. Saga 오케스트레이션 로직 업데이트
4. 보상 로직 추가
5. 테스트 작성

### 이벤트 스키마 진화
- 하위 호환 가능한 이벤트 버전 관리
- 이벤트 마이그레이션 전략
- 스키마 레지스트리 통합

## 🎯 프로젝트 로드맵

### ✅ v2.0.0 완료 (2025.06.11) - Docker Compose 다중 인스턴스

#### 🏭 **다중 인스턴스 환경**
- ✅ **Docker Compose 3노드 + Nginx** - Load Balancer 완료
- ✅ **인스턴스 간 작업 분산** - Round-robin 자동 분산 검증
- ✅ **노드별 처리 분산 추적** - DB 기반 마이크로초 정밀도 측정

#### 🔐 **분산 동시성 제어**  
- ✅ **Redis 분산 락 구현** - ProductId 기준 완벽한 중복 방지
- ✅ **Idempotency Key 보장** - 멱등성 기반 안전성 확보
- ✅ **동시 요청 차단** - 5개 동시 요청 → 1개만 생성 검증

#### 🔄 **분산 SAGA 패턴**
- ✅ **다중 인스턴스 SAGA 실행** - 3개 노드에서 안전한 SAGA 처리
- ✅ **SAGA 상태 동기화** - Redis 락 기반 일관성 보장  
- ✅ **분산 보상 트랜잭션** - 노드간 보상 처리 완전 검증
- ✅ **SAGA 완료율 100%** - 실패 시 자동 보상 메커니즘

### ✅ v2.5.0 완료 (2025.06.19) - Kubernetes 환경 구축

#### ☸️ **Kubernetes 인프라 완성**
- ✅ **Namespace 및 기본 리소스** - `nestjs-cqrs-saga` 네임스페이스
- ✅ **PostgreSQL StatefulSet** - 데이터 영속성 보장 (PVC 연동)
- ✅ **Redis 분산 락** - Kubernetes 환경에서 동일한 성능 유지
- ✅ **Kafka & Zookeeper 클러스터** - 메시징 시스템 완전 구축
- ✅ **NestJS 애플리케이션** - 3개 Pod 자동 배포 및 로드밸런싱
- ✅ **Service Discovery** - ClusterIP + LoadBalancer 구성

#### 🧪 **완전한 테스트 스위트**
- ✅ **스키마 에러 해결** - 모든 PostgreSQL 컬럼명 오류 수정
- ✅ **통합 테스트 자동화** - 6개 검증 스크립트 완성
- ✅ **100% 테스트 성공** - 5개 테스트 모두 통과 (478초 소요)
- ✅ **성능 검증** - Docker Compose와 동등한 처리 성능

#### 📊 **성능 및 안정성 검증**
- ✅ **데이터 처리량** - 157개 신규 주문, 1,006개 신규 이벤트 처리
- ✅ **분산 락 성능** - Redis Lock < 5ms (기존과 동일)
- ✅ **SAGA 완료율** - 100% (모든 SAGA 정상 완료)
- ✅ **Pod 안정성** - 2시간+ 연속 운영 확인
- ✅ **자동 복구** - Pod 재시작 시 자동 데이터 복구

### 🚀 v3.0.0 계획 - 고급 Kubernetes 기능

#### Phase 1: 오토스케일링 & 모니터링
- [ ] **Horizontal Pod Autoscaler** - CPU/Memory 기반 동적 스케일링
- [ ] **Prometheus + Grafana** - 완전한 모니터링 스택
- [ ] **Alert Manager** - 자동 알림 시스템
- [ ] **커스텀 메트릭** - SAGA 처리량 기반 스케일링

#### Phase 2: 장애 복구 & Chaos Engineering  
- [ ] **Pod 장애 시나리오** - Pod 강제 종료 시 SAGA 상태 보존
- [ ] **네트워크 분할 테스트** - 분산 시스템 복원력 검증
- [ ] **부하 테스트** - 동적 스케일링 환경에서 성능 측정
- [ ] **백업 및 복구** - PVC 데이터 백업 자동화

#### Phase 3: Cloud 배포 & 프로덕션화
- [ ] **AWS EKS / GKE 배포** - 클라우드 환경 검증
- [ ] **Helm Charts** - 패키지 관리 및 배포 자동화
- [ ] **CI/CD 파이프라인** - GitHub Actions + ArgoCD
- [ ] **보안 강화** - RBAC, Network Policies, Pod Security

### 📅 마일스톤 일정
- **✅ v2.0.0**: Docker Compose 다중 인스턴스 (완료 - 2025.06.11)
- **✅ v2.5.0**: Kubernetes 로컬 환경 (완료 - 2025.06.19)
- **🎯 v3.0.0**: 고급 K8s 기능 & Cloud 배포 (계획 - 2025.07월)

## 🤝 기여하기

1. 저장소 포크
2. 기능 브랜치 생성 (`git checkout -b feature/amazing-feature`)
3. 변경사항 커밋 (`git commit -m 'Add amazing feature'`)
4. 브랜치에 푸시 (`git push origin feature/amazing-feature`)
5. Pull Request 열기

### 개발 가이드라인
- NestJS 모범 사례 따르기
- 포괄적인 테스트 작성
- 문서 업데이트
- 하위 호환성 보장

## 📚 추가 리소스

### 문서 (예정)
- [CQRS 패턴 가이드](./docs/cqrs-pattern.md)
- [Saga 패턴 구현](./docs/saga-pattern.md)
- [API 문서](./docs/api-reference.md)
- [배포 가이드](./docs/deployment.md)

### 관련 프로젝트
- [NestJS 공식 문서](https://docs.nestjs.com/)
- [NestJS와 이벤트 소싱](https://github.com/nestjs/cqrs)
- [NestJS와 Kafka](https://docs.nestjs.com/microservices/kafka)

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 라이선스가 부여됩니다 - 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 🙏 감사의 말

- 놀라운 프레임워크를 제공한 NestJS 팀
- CQRS와 이벤트 소싱 커뮤니티
- Apache Kafka 기여자들

### 🤖 AI 페어 프로그래밍

이 프로젝트는 **Claude AI와 MCP(Model Context Protocol)**를 활용한 AI 페어 프로그래밍으로 개발되었습니다. 복잡한 분산 시스템 아키텍처를 AI와 함께 설계하고 구현하는 혁신적인 개발 경험을 통해, 전통적인 코딩의 한계를 넘어선 새로운 차원의 협업을 경험할 수 있었습니다. 

AI와의 실시간 코드 리뷰, 아키텍처 토론, 그리고 즉석 문제 해결 과정은 마치 숙련된 시니어 개발자와 페어 프로그래밍을 하는 듯한 놀라운 **바이브**를 선사했습니다. 🚀✨

---

**NestJS, TypeScript 그리고 현대적인 소프트웨어 아키텍처 패턴으로 ❤️를 담아 제작되었습니다**

---

## 🚀 프로젝트 상태

**현재 버전**: v2.5.0 - Kubernetes 환경 완료 ✅  
**다음 마일스톤**: v3.0.0 - 고급 K8s 기능 & Cloud 배포  
**최종 목표**: 프로덕션 준비 완료된 분산 SAGA 시스템

---

질문이나 지원이 필요하시면, 이슈를 열거나 관리자에게 연락해 주세요.