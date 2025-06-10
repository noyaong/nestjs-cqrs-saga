import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  getHello(): string {
    return 'Hello! NestJS CQRS Saga 프로젝트에 오신 것을 환영합니다! 🚀';
  }
}