FROM node:18-alpine

WORKDIR /app

# 패키지 파일들 복사  
COPY package*.json ./

# 의존성 설치
RUN npm install

# 애플리케이션 코드 복사
COPY . .

# TypeScript 빌드
RUN npm run build

# 로그 디렉토리 생성
RUN mkdir -p logs

# 애플리케이션 실행 사용자 생성
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nestjs -u 1001

# 로그 디렉토리 권한 설정
RUN chown -R nestjs:nodejs /app/logs

USER nestjs

EXPOSE 3000

CMD ["npm", "run", "start:prod"] 