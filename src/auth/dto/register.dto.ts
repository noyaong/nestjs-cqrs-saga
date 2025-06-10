import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsString, MinLength, MaxLength } from 'class-validator';

export class RegisterDto {
  @ApiProperty({
    example: 'john@example.com',
    description: '사용자 이메일',
  })
  @IsEmail()
  email: string;

  @ApiProperty({
    example: 'password123',
    description: '비밀번호 (최소 8자)',
    minLength: 8,
  })
  @IsString()
  @MinLength(8)
  password: string;

  @ApiProperty({
    example: 'John',
    description: '이름',
  })
  @IsString()
  @MaxLength(50)
  firstName: string;

  @ApiProperty({
    example: 'Doe',
    description: '성',
  })
  @IsString()
  @MaxLength(50)
  lastName: string;
}