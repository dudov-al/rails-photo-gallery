class SecurityEvent < ApplicationRecord
  # Security audit trail model
  
  belongs_to :photographer, optional: true
  
  validates :event_type, presence: true
  validates :ip_address, presence: true, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z|\A(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\z/ }
  validates :severity, inclusion: { in: %w[LOW MEDIUM HIGH CRITICAL] }
  validates :occurred_at, presence: true
  
  scope :recent, -> { order(occurred_at: :desc) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :by_event_type, ->(event_type) { where(event_type: event_type) }
  scope :by_ip, ->(ip) { where(ip_address: ip) }
  scope :in_timeframe, ->(start_time, end_time = Time.current) { where(occurred_at: start_time..end_time) }
  scope :suspicious, -> { where(event_type: ['session_hijack_attempt', 'suspicious_activity', 'file_upload_blocked']) }
  scope :authentication_events, -> { where(event_type: ['successful_login', 'failed_login_attempt', 'account_locked']) }
  
  # Class methods for analysis
  def self.failed_login_attempts_for_ip(ip_address, timeframe = 1.hour)
    where(
      event_type: 'failed_login_attempt',
      ip_address: ip_address,
      occurred_at: timeframe.ago..Time.current
    ).count
  end
  
  def self.suspicious_activity_for_ip(ip_address, timeframe = 24.hours)
    suspicious.where(
      ip_address: ip_address,
      occurred_at: timeframe.ago..Time.current
    )
  end
  
  def self.attack_patterns
    {
      brute_force_ips: where(event_type: 'failed_login_attempt')
                         .where('occurred_at >= ?', 1.hour.ago)
                         .group(:ip_address)
                         .having('COUNT(*) >= ?', 10)
                         .count,
      
      locked_accounts: where(event_type: 'account_locked')
                         .where('occurred_at >= ?', 24.hours.ago)
                         .count,
      
      csp_violations: where(event_type: 'csp_violation')
                        .where('occurred_at >= ?', 1.hour.ago)
                        .count
    }
  end
  
  def self.security_report(timeframe = 24.hours)
    events = where('occurred_at >= ?', timeframe.ago)
    
    {
      timeframe: "Last #{timeframe.inspect}",
      total_events: events.count,
      events_by_type: events.group(:event_type).count,
      events_by_severity: events.group(:severity).count,
      unique_ips: events.distinct.count(:ip_address),
      top_ips: events.group(:ip_address).count.sort_by { |k, v| -v }.first(10),
      attack_patterns: attack_patterns,
      recent_critical: events.by_severity('HIGH').recent.limit(10).pluck(:event_type, :ip_address, :occurred_at)
    }
  end
  
  # Instance methods
  def critical?
    %w[HIGH CRITICAL].include?(severity)
  end
  
  def authentication_related?
    %w[successful_login failed_login_attempt account_locked].include?(event_type)
  end
  
  def display_name
    event_type.humanize
  end
  
  def geographic_location
    # Placeholder for IP geolocation lookup
    # Could integrate with MaxMind GeoIP or similar service
    @geographic_location ||= "Unknown"
  end
  
  def threat_level
    case severity
    when 'CRITICAL'
      5
    when 'HIGH'
      4
    when 'MEDIUM'
      3
    when 'LOW'
      2
    else
      1
    end
  end
end