require 'rails_helper'

RSpec.describe SecurityEvent, type: :model do
  let(:photographer) { create(:photographer) }
  let(:security_event) { build(:security_event, photographer: photographer) }

  describe 'associations' do
    it { should belong_to(:photographer).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:ip_address) }
    it { should validate_presence_of(:occurred_at) }

    describe 'IP address validation' do
      it 'accepts valid IPv4 addresses' do
        valid_ipv4s = %w[127.0.0.1 192.168.1.1 203.0.113.1 10.0.0.1]
        valid_ipv4s.each do |ip|
          security_event.ip_address = ip
          expect(security_event).to be_valid, "#{ip} should be valid IPv4"
        end
      end

      it 'accepts valid IPv6 addresses' do
        valid_ipv6s = %w[::1 2001:db8::1 fe80::1 2001:0db8:85a3:0000:0000:8a2e:0370:7334]
        valid_ipv6s.each do |ip|
          security_event.ip_address = ip
          expect(security_event).to be_valid, "#{ip} should be valid IPv6"
        end
      end

      it 'rejects invalid IP addresses' do
        invalid_ips = %w[256.1.1.1 192.168.1 not.an.ip.address 999.999.999.999]
        invalid_ips.each do |ip|
          security_event.ip_address = ip
          expect(security_event).to_not be_valid, "#{ip} should be invalid"
        end
      end
    end

    describe 'severity validation' do
      it 'accepts valid severity levels' do
        valid_severities = %w[LOW MEDIUM HIGH CRITICAL]
        valid_severities.each do |severity|
          security_event.severity = severity
          expect(security_event).to be_valid, "#{severity} should be valid"
        end
      end

      it 'rejects invalid severity levels' do
        invalid_severities = %w[low EXTREME NONE invalid]
        invalid_severities.each do |severity|
          security_event.severity = severity
          expect(security_event).to_not be_valid, "#{severity} should be invalid"
        end
      end
    end
  end

  describe 'scopes' do
    let!(:recent_event) { create(:security_event, occurred_at: 1.hour.ago) }
    let!(:old_event) { create(:security_event, occurred_at: 1.week.ago) }
    let!(:high_severity_event) { create(:security_event, severity: 'HIGH') }
    let!(:low_severity_event) { create(:security_event, severity: 'LOW') }
    let!(:login_event) { create(:security_event, event_type: 'successful_login') }
    let!(:suspicious_event) { create(:security_event, :suspicious_activity) }
    let!(:ip_specific_event) { create(:security_event, ip_address: '192.168.1.100') }

    describe '.recent' do
      it 'orders by occurred_at descending' do
        expect(SecurityEvent.recent.first).to eq(recent_event)
        expect(SecurityEvent.recent.last).to eq(old_event)
      end
    end

    describe '.by_severity' do
      it 'filters by severity level' do
        expect(SecurityEvent.by_severity('HIGH')).to include(high_severity_event)
        expect(SecurityEvent.by_severity('HIGH')).not_to include(low_severity_event)
      end
    end

    describe '.by_event_type' do
      it 'filters by event type' do
        expect(SecurityEvent.by_event_type('successful_login')).to include(login_event)
        expect(SecurityEvent.by_event_type('successful_login')).not_to include(suspicious_event)
      end
    end

    describe '.by_ip' do
      it 'filters by IP address' do
        expect(SecurityEvent.by_ip('192.168.1.100')).to include(ip_specific_event)
        expect(SecurityEvent.by_ip('192.168.1.100')).not_to include(recent_event)
      end
    end

    describe '.in_timeframe' do
      it 'filters by time range' do
        events = SecurityEvent.in_timeframe(2.hours.ago, Time.current)
        expect(events).to include(recent_event)
        expect(events).not_to include(old_event)
      end

      it 'defaults end time to current time' do
        events = SecurityEvent.in_timeframe(2.hours.ago)
        expect(events).to include(recent_event)
      end
    end

    describe '.suspicious' do
      let!(:hijack_event) { create(:security_event, :session_hijack_attempt) }
      let!(:blocked_upload) { create(:security_event, :file_upload_blocked) }

      it 'includes suspicious event types' do
        expect(SecurityEvent.suspicious).to include(suspicious_event, hijack_event, blocked_upload)
        expect(SecurityEvent.suspicious).not_to include(login_event)
      end
    end

    describe '.authentication_events' do
      let!(:failed_login) { create(:security_event, :failed_login) }
      let!(:locked_account) { create(:security_event, :account_locked) }

      it 'includes authentication-related events' do
        expect(SecurityEvent.authentication_events).to include(login_event, failed_login, locked_account)
        expect(SecurityEvent.authentication_events).not_to include(suspicious_event)
      end
    end
  end

  describe 'class methods' do
    describe '.failed_login_attempts_for_ip' do
      let(:ip_address) { '192.168.1.100' }
      
      before do
        create_list(:security_event, 3, :failed_login, ip_address: ip_address, occurred_at: 30.minutes.ago)
        create(:security_event, :failed_login, ip_address: ip_address, occurred_at: 2.hours.ago) # Outside timeframe
        create(:security_event, :failed_login, ip_address: '192.168.1.101', occurred_at: 15.minutes.ago) # Different IP
      end

      it 'counts failed login attempts for specific IP within timeframe' do
        count = SecurityEvent.failed_login_attempts_for_ip(ip_address, 1.hour)
        expect(count).to eq(3)
      end

      it 'uses default timeframe of 1 hour' do
        count = SecurityEvent.failed_login_attempts_for_ip(ip_address)
        expect(count).to eq(3)
      end
    end

    describe '.suspicious_activity_for_ip' do
      let(:ip_address) { '203.0.113.1' }

      before do
        create(:security_event, :suspicious_activity, ip_address: ip_address, occurred_at: 1.hour.ago)
        create(:security_event, :session_hijack_attempt, ip_address: ip_address, occurred_at: 2.hours.ago)
        create(:security_event, :file_upload_blocked, ip_address: ip_address, occurred_at: 30.hours.ago) # Outside timeframe
      end

      it 'returns suspicious events for IP within timeframe' do
        events = SecurityEvent.suspicious_activity_for_ip(ip_address, 24.hours)
        expect(events.count).to eq(2)
      end
    end

    describe '.attack_patterns' do
      before do
        # Create brute force pattern
        create_list(:security_event, 12, :failed_login, ip_address: '198.51.100.1', occurred_at: 30.minutes.ago)
        
        # Create locked accounts
        create_list(:security_event, 3, :account_locked, occurred_at: 12.hours.ago)
        
        # Create CSP violations
        create_list(:security_event, 5, :csp_violation, occurred_at: 30.minutes.ago)
      end

      it 'identifies attack patterns' do
        patterns = SecurityEvent.attack_patterns
        
        expect(patterns[:brute_force_ips]).to have_key('198.51.100.1')
        expect(patterns[:brute_force_ips]['198.51.100.1']).to eq(12)
        expect(patterns[:locked_accounts]).to eq(3)
        expect(patterns[:csp_violations]).to eq(5)
      end
    end

    describe '.security_report' do
      before do
        create(:security_event, :successful_login, occurred_at: 2.hours.ago)
        create(:security_event, :failed_login, occurred_at: 1.hour.ago)
        create(:security_event, :suspicious_activity, severity: 'HIGH', occurred_at: 30.minutes.ago)
        create(:security_event, :old) # Outside timeframe
      end

      it 'generates comprehensive security report' do
        report = SecurityEvent.security_report(24.hours)
        
        expect(report[:total_events]).to eq(3)
        expect(report[:events_by_type]).to have_key('successful_login')
        expect(report[:events_by_severity]).to have_key('HIGH')
        expect(report[:unique_ips]).to be > 0
        expect(report[:top_ips]).to be_an(Array)
        expect(report[:attack_patterns]).to be_a(Hash)
        expect(report[:recent_critical]).to be_an(Array)
      end

      it 'respects timeframe parameter' do
        report = SecurityEvent.security_report(1.hour)
        expect(report[:total_events]).to be < 3
      end
    end
  end

  describe 'instance methods' do
    describe '#critical?' do
      it 'returns true for HIGH and CRITICAL severity' do
        high_event = build(:security_event, severity: 'HIGH')
        critical_event = build(:security_event, severity: 'CRITICAL')
        
        expect(high_event.critical?).to be true
        expect(critical_event.critical?).to be true
      end

      it 'returns false for LOW and MEDIUM severity' do
        low_event = build(:security_event, severity: 'LOW')
        medium_event = build(:security_event, severity: 'MEDIUM')
        
        expect(low_event.critical?).to be false
        expect(medium_event.critical?).to be false
      end
    end

    describe '#authentication_related?' do
      it 'returns true for authentication events' do
        auth_events = %w[successful_login failed_login_attempt account_locked]
        
        auth_events.each do |event_type|
          event = build(:security_event, event_type: event_type)
          expect(event.authentication_related?).to be true
        end
      end

      it 'returns false for non-authentication events' do
        non_auth_events = %w[suspicious_activity file_upload_blocked csp_violation]
        
        non_auth_events.each do |event_type|
          event = build(:security_event, event_type: event_type)
          expect(event.authentication_related?).to be false
        end
      end
    end

    describe '#display_name' do
      it 'humanizes event type' do
        event = build(:security_event, event_type: 'failed_login_attempt')
        expect(event.display_name).to eq('Failed login attempt')
      end

      it 'handles underscores in event types' do
        event = build(:security_event, event_type: 'session_hijack_attempt')
        expect(event.display_name).to eq('Session hijack attempt')
      end
    end

    describe '#geographic_location' do
      it 'returns unknown for now' do
        # Placeholder implementation
        expect(security_event.geographic_location).to eq('Unknown')
      end
    end

    describe '#threat_level' do
      it 'assigns numeric threat levels based on severity' do
        severity_levels = {
          'CRITICAL' => 5,
          'HIGH' => 4,
          'MEDIUM' => 3,
          'LOW' => 2
        }

        severity_levels.each do |severity, expected_level|
          event = build(:security_event, severity: severity)
          expect(event.threat_level).to eq(expected_level)
        end
      end

      it 'defaults to 1 for unknown severity' do
        event = build(:security_event, severity: 'UNKNOWN')
        expect(event.threat_level).to eq(1)
      end
    end
  end

  describe 'factory traits' do
    it 'creates different event types correctly' do
      event_types = {
        :failed_login => 'failed_login_attempt',
        :account_locked => 'account_locked',
        :gallery_auth_success => 'gallery_auth_success',
        :suspicious_activity => 'suspicious_activity',
        :session_hijack_attempt => 'session_hijack_attempt'
      }

      event_types.each do |trait, expected_type|
        event = create(:security_event, trait)
        expect(event.event_type).to eq(expected_type)
      end
    end

    it 'sets appropriate severity levels' do
      severity_tests = {
        :failed_login => 'MEDIUM',
        :account_locked => 'HIGH',
        :session_hijack_attempt => 'CRITICAL',
        :suspicious_activity => 'HIGH'
      }

      severity_tests.each do |trait, expected_severity|
        event = create(:security_event, trait)
        expect(event.severity).to eq(expected_severity)
      end
    end

    it 'includes relevant additional data' do
      event = create(:security_event, :failed_login)
      expect(event.additional_data['email']).to be_present
      expect(event.additional_data['failed_attempts']).to be_present
      expect(event.additional_data['reason']).to eq('incorrect_password')
    end
  end

  describe 'anonymous events' do
    it 'allows events without photographer association' do
      event = create(:security_event, :anonymous)
      expect(event.photographer).to be_nil
      expect(event).to be_valid
    end
  end

  describe 'data integrity' do
    it 'properly stores JSON in additional_data field' do
      complex_data = {
        'nested' => { 'key' => 'value' },
        'array' => [1, 2, 3],
        'boolean' => true,
        'number' => 42
      }

      event = create(:security_event, additional_data: complex_data)
      event.reload
      
      expect(event.additional_data['nested']['key']).to eq('value')
      expect(event.additional_data['array']).to eq([1, 2, 3])
      expect(event.additional_data['boolean']).to be true
      expect(event.additional_data['number']).to eq(42)
    end
  end

  describe 'performance considerations' do
    it 'efficiently handles large datasets in analysis methods' do
      # Create a reasonable number of events for testing
      create_list(:security_event, 50, occurred_at: 1.hour.ago)
      
      expect { SecurityEvent.attack_patterns }.not_to exceed_query_limit(5)
      expect { SecurityEvent.security_report }.not_to exceed_query_limit(10)
    end
  end
end