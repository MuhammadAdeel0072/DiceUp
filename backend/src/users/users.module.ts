import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { AuthSession } from '../auth/entities/auth-session.entity';
import { Profile } from './entities/profile.entity';
import { User } from './entities/user.entity';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

/**
 * UsersModule (plan §3.2). Profile management, password change,
 * preferences, public profiles, deletion requests. No admin endpoints
 * (Phase 7). PasswordHasherService comes from AuthModule.
 */
@Module({
  imports: [TypeOrmModule.forFeature([User, Profile, AuthSession]), AuthModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
