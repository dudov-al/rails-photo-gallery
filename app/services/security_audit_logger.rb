class SecurityAuditLogger
  # Centralized security event logging service
  
  SECURITY_EVENTS = %w[
    successful_login
    failed_login_attempt
    account_locked
    account_locked_login_attempt
    account_created
    password_changed
    session_hijack_attempt
    suspicious_activity
    file_upload_blocked
    rate_limit_exceeded
    csp_violation
    logout
    session_expired
    ip_blocked_excessive_attempts
  ].freeze
  
  def self.log(event_type:, ip_address: nil, photographer_id: nil, session_id: nil, user_agent: nil, additional_data: {})
    # Validate event type
    unless SECURITY_EVENTS.include?(event_type.to_s)
      Rails.logger.warn "[SECURITY] Unknown event type: #{event_type}"
      return
    end
    
    # Create structured log entry
    log_entry = {
      timestamp: Time.current.iso8601,
      event_type: event_type,
      ip_address: ip_address,
      photographer_id: photographer_id,
      session_id: session_id,
      user_agent: user_agent,
      severity: determine_severity(event_type),
      additional_data: additional_data
    }
    
    # Log to Rails logger with structured format
    Rails.logger.security.info("[SECURITY] #{log_entry.to_json}")
    
    # Store in database if configured
    store_in_database(log_entry) if should_store_in_database?
    
    # Send alerts for critical events
    send_alert(log_entry) if critical_event?(event_type)
    
    # Update security metrics
    update_security_metrics(event_type, ip_address)
    
    log_entry
  rescue => e
    Rails.logger.error "[SECURITY LOGGER ERROR] #{e.message}: #{e.backtrace.first}"
    nil
  end
  
  def self.log_csp_violation(violation_data)
    log(
      event_type: 'csp_violation',
      ip_address: violation_data[:ip],
      additional_data: {
        blocked_uri: violation_data[:blocked_uri],
        document_uri: violation_data[:document_uri],
        violated_directive: violation_data[:violated_directive],
        original_policy: violation_data[:original_policy]
      }
    )
  end
  
  def self.get_security_summary(timeframe = 24.hours)
    events = SecurityEvent.where('created_at >= ?', timeframe.ago)
    
    {
      total_events: events.count,
      failed_logins: events.where(event_type: 'failed_login_attempt').count,
      locked_accounts: events.where(event_type: 'account_locked').count,
      suspicious_activities: events.where(event_type: 'suspicious_activity').count,
      unique_ips: events.distinct.count(:ip_address),
      top_attacking_ips: events.group(:ip_address).count.sort_by { |k, v| -v }.first(10)
    }
  end
  
  private
  
  def self.determine_severity(event_type)
    case event_type.to_s
    when 'account_locked', 'session_hijack_attempt', 'suspicious_activity'
      'HIGH'
    when 'failed_login_attempt', 'rate_limit_exceeded', 'file_upload_blocked'
      'MEDIUM'
    when 'successful_login', 'logout', 'account_created'
      'LOW'
    else
      'MEDIUM'
    end
  end
  
  def self.critical_event?(event_type)
    %w[account_locked session_hijack_attempt suspicious_activity].include?(event_type.to_s)
  end
  
  def self.should_store_in_database?
    Rails.env.production? && defined?(SecurityEvent)
  end
  
  def self.store_in_database(log_entry)
    SecurityEvent.create!(
      event_type: log_entry[:event_type],
      photographer_id: log_entry[:photographer_id],
      ip_address: log_entry[:ip_address],
      session_id: log_entry[:session_id],
      user_agent: log_entry[:user_agent],
      severity: log_entry[:severity],
      additional_data: log_entry[:additional_data],
      occurred_at: log_entry[:timestamp]
    )
  rescue => e
    Rails.logger.error "[SECURITY EVENT STORAGE ERROR] #{e.message}"
  end
  
  def self.send_alert(log_entry)
    return unless Rails.env.production?
    
    # Send to monitoring service (implement based on your monitoring setup)
    # SecurityAlertJob.perform_later(log_entry)
    
    Rails.logger.error "[CRITICAL SECURITY EVENT] #{log_entry.to_json}"
  end
  
  def self.update_security_metrics(event_type, ip_address)
    return unless ip_address
    
    # Track IP-based metrics in Redis/cache
    Rails.cache.increment("security:#{event_type}:#{ip_address}", 1, expires_in: 24.hours)
    Rails.cache.increment("security:#{event_type}:total", 1, expires_in: 24.hours)
  rescue => e
    Rails.logger.error "[SECURITY METRICS ERROR] #{e.message}"
  end
end