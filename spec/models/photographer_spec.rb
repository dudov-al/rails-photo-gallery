require 'rails_helper'

RSpec.describe Photographer, type: :model do
  let(:photographer) { build(:photographer) }

  describe 'associations' do
    it { should have_many(:galleries).dependent(:destroy) }
    it { should have_many(:images).through(:galleries) }
    it { should have_many(:security_events).dependent(:destroy) }
  end

  describe 'validations' do
    context 'email validation' do
      it { should validate_presence_of(:email) }
      it { should validate_uniqueness_of(:email).case_insensitive }
      
      it 'accepts valid email addresses' do
        valid_emails = %w[user@example.com test.email+tag@domain.co.uk]
        valid_emails.each do |email|
          photographer.email = email
          expect(photographer).to be_valid, "#{email} should be valid"
        end
      end

      it 'rejects invalid email addresses' do
        invalid_emails = %w[invalid.email @domain.com user@]
        invalid_emails.each do |email|
          photographer.email = email
          expect(photographer).to_not be_valid, "#{email} should be invalid"
        end
      end
    end

    context 'name validation' do
      it { should validate_presence_of(:name) }
      it { should validate_length_of(:name).is_at_least(2).is_at_most(100) }

      it 'rejects names that are too short' do
        photographer.name = 'A'
        expect(photographer).to_not be_valid
        expect(photographer.errors[:name]).to include('is too short (minimum is 2 characters)')
      end

      it 'rejects names that are too long' do
        photographer.name = 'A' * 101
        expect(photographer).to_not be_valid
        expect(photographer.errors[:name]).to include('is too long (maximum is 100 characters)')
      end
    end

    context 'password validation' do
      it 'requires password to be at least 8 characters' do
        photographer.password = 'Short1!'
        photographer.password_confirmation = 'Short1!'
        expect(photographer).to_not be_valid
        expect(photographer.errors[:password]).to include('is too short (minimum is 8 characters)')
      end

      it 'requires password to contain at least one lowercase letter' do
        photographer.password = 'PASSWORD123!'
        photographer.password_confirmation = 'PASSWORD123!'
        expect(photographer).to_not be_valid
        expect(photographer.errors[:password]).to include('must include at least one lowercase letter, one uppercase letter, and one number')
      end

      it 'requires password to contain at least one uppercase letter' do
        photographer.password = 'password123!'
        photographer.password_confirmation = 'password123!'
        expect(photographer).to_not be_valid
        expect(photographer.errors[:password]).to include('must include at least one lowercase letter, one uppercase letter, and one number')
      end

      it 'requires password to contain at least one number' do
        photographer.password = 'Password!'
        photographer.password_confirmation = 'Password!'
        expect(photographer).to_not be_valid
        expect(photographer.errors[:password]).to include('must include at least one lowercase letter, one uppercase letter, and one number')
      end

      it 'accepts valid strong passwords' do
        photographer.password = 'StrongPassword123!'
        photographer.password_confirmation = 'StrongPassword123!'
        expect(photographer).to be_valid
      end
    end
  end

  describe 'callbacks' do
    describe 'before_save :normalize_email' do
      it 'downcases and strips email' do
        photographer.email = '  USER@EXAMPLE.COM  '
        photographer.save
        expect(photographer.email).to eq('user@example.com')
      end
    end

    describe 'after_create :log_account_creation' do
      it 'logs account creation security event' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'account_created',
          photographer_id: anything,
          ip_address: nil,
          additional_data: hash_including(:email)
        )
        
        create(:photographer)
      end
    end
  end

  describe 'scopes' do
    let!(:active_photographer) { create(:photographer, active: true) }
    let!(:inactive_photographer) { create(:photographer, active: false) }
    let!(:locked_photographer) { create(:photographer, :locked) }
    let!(:photographer_with_galleries) { create(:photographer, :with_galleries) }

    describe '.active' do
      it 'returns only active photographers' do
        expect(Photographer.active).to include(active_photographer)
        expect(Photographer.active).not_to include(inactive_photographer)
      end
    end

    describe '.locked' do
      it 'returns only locked photographers' do
        expect(Photographer.locked).to include(locked_photographer)
        expect(Photographer.locked).not_to include(active_photographer)
      end
    end

    describe '.unlocked' do
      it 'returns unlocked photographers' do
        expect(Photographer.unlocked).to include(active_photographer)
        expect(Photographer.unlocked).not_to include(locked_photographer)
      end
    end

    describe '.with_galleries' do
      it 'returns photographers who have galleries' do
        expect(Photographer.with_galleries).to include(photographer_with_galleries)
        expect(Photographer.with_galleries).not_to include(active_photographer)
      end
    end
  end

  describe 'security methods' do
    describe '#account_locked?' do
      context 'when locked_until is in the future' do
        let(:photographer) { create(:photographer, :locked) }

        it 'returns true' do
          expect(photographer.account_locked?).to be true
        end
      end

      context 'when locked_until is in the past' do
        let(:photographer) { create(:photographer, locked_until: 1.hour.ago) }

        it 'returns false' do
          expect(photographer.account_locked?).to be false
        end
      end

      context 'when locked_until is nil' do
        let(:photographer) { create(:photographer) }

        it 'returns false' do
          expect(photographer.account_locked?).to be false
        end
      end
    end

    describe '#increment_failed_attempts!' do
      let(:photographer) { create(:photographer) }

      before do
        allow(Current).to receive(:request_ip).and_return('127.0.0.1')
      end

      it 'increments failed attempts count' do
        expect { photographer.increment_failed_attempts! }.to change(photographer, :failed_attempts).from(0).to(1)
      end

      it 'sets last_failed_attempt timestamp' do
        photographer.increment_failed_attempts!
        expect(photographer.last_failed_attempt).to be_within(1.second).of(Time.current)
      end

      it 'locks account when max attempts reached' do
        photographer.update!(failed_attempts: 4)
        photographer.increment_failed_attempts!
        
        expect(photographer.failed_attempts).to eq(5)
        expect(photographer.locked_until).to be_present
        expect(photographer.locked_until).to be > Time.current
      end

      it 'logs security events' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'failed_login_attempt',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:email, :failed_attempts)
        )

        photographer.increment_failed_attempts!
      end

      it 'logs account_locked event when threshold reached' do
        photographer.update!(failed_attempts: 4)
        
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'account_locked',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:email, :locked_until)
        )

        photographer.increment_failed_attempts!
      end
    end

    describe '#reset_failed_attempts!' do
      let(:photographer) { create(:photographer, :with_failed_attempts) }

      before do
        allow(Current).to receive(:request_ip).and_return('127.0.0.1')
      end

      it 'resets failed attempts to zero' do
        photographer.reset_failed_attempts!
        expect(photographer.failed_attempts).to eq(0)
      end

      it 'clears locked_until' do
        photographer.update!(locked_until: 1.hour.from_now)
        photographer.reset_failed_attempts!
        expect(photographer.locked_until).to be_nil
      end

      it 'sets last_login_at and last_login_ip' do
        photographer.reset_failed_attempts!
        expect(photographer.last_login_at).to be_within(1.second).of(Time.current)
        expect(photographer.last_login_ip).to eq('127.0.0.1')
      end

      it 'logs successful login event' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'successful_login',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:email)
        )

        photographer.reset_failed_attempts!
      end
    end

    describe '#authenticate_with_security' do
      let(:photographer) { create(:photographer, password: 'ValidPassword123!') }

      context 'with correct password and unlocked account' do
        it 'returns true and resets failed attempts' do
          expect(photographer).to receive(:reset_failed_attempts!)
          result = photographer.authenticate_with_security('ValidPassword123!')
          expect(result).to be true
        end
      end

      context 'with incorrect password' do
        it 'returns false and increments failed attempts' do
          expect(photographer).to receive(:increment_failed_attempts!)
          result = photographer.authenticate_with_security('WrongPassword')
          expect(result).to be false
        end
      end

      context 'with locked account' do
        let(:photographer) { create(:photographer, :locked) }

        it 'returns false without checking password' do
          expect(photographer).not_to receive(:authenticate)
          result = photographer.authenticate_with_security('ValidPassword123!')
          expect(result).to be false
        end
      end
    end

    describe '#password_strength_score' do
      it 'returns 0 for missing password' do
        photographer.password = nil
        expect(photographer.password_strength_score).to eq(0)
      end

      it 'calculates score based on complexity factors' do
        test_cases = [
          { password: 'short', expected: 1 },  # only length >= 8 fails
          { password: 'password', expected: 2 }, # length + lowercase
          { password: 'Password', expected: 3 }, # length + lowercase + uppercase  
          { password: 'Password1', expected: 4 }, # + number
          { password: 'Password1!', expected: 5 }, # + special char
          { password: 'VeryLongPassword1!', expected: 6 } # + length >= 12
        ]

        test_cases.each do |test_case|
          photographer.password = test_case[:password]
          expect(photographer.password_strength_score).to eq(test_case[:expected])
        end
      end
    end

    describe '#time_until_unlock' do
      context 'when account is locked' do
        let(:photographer) { create(:photographer, locked_until: 15.minutes.from_now) }

        it 'returns minutes until unlock' do
          expect(photographer.time_until_unlock).to be_between(14, 16)
        end
      end

      context 'when account is not locked' do
        let(:photographer) { create(:photographer) }

        it 'returns 0' do
          expect(photographer.time_until_unlock).to eq(0)
        end
      end
    end
  end

  describe 'email normalization' do
    it 'normalizes email before saving' do
      photographer = build(:photographer, email: '  TEST@EXAMPLE.COM  ')
      photographer.save
      expect(photographer.email).to eq('test@example.com')
    end

    it 'handles nil email gracefully' do
      photographer.email = nil
      expect { photographer.save }.not_to raise_error
    end
  end

  describe 'class constants' do
    it 'has correct security configuration' do
      expect(Photographer::MAX_FAILED_ATTEMPTS).to eq(5)
      expect(Photographer::LOCKOUT_DURATION).to eq(30.minutes)
    end
  end
end