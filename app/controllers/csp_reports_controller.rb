class CspReportsController < ApplicationController
  # Skip CSRF protection for CSP violation reports
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_photographer!
  
  def create
    violation_data = parse_csp_violation(request.raw_post)
    
    if violation_data
      # Log CSP violation using security audit logger
      SecurityAuditLogger.log_csp_violation({
        ip: request.remote_ip,
        blocked_uri: violation_data['blocked-uri'],
        document_uri: violation_data['document-uri'],
        violated_directive: violation_data['violated-directive'],
        original_policy: violation_data['original-policy'],
        user_agent: request.user_agent,
        referrer: violation_data['referrer'],
        status_code: violation_data['status-code']
      })
      
      # In production, you might want to send this to monitoring service
      if Rails.env.production?
        Rails.logger.warn "[CSP VIOLATION] #{violation_data.to_json}"
      end
    end
    
    head :no_content
  rescue => e
    Rails.logger.error "[CSP REPORT ERROR] #{e.message}: #{request.raw_post}"
    head :bad_request
  end
  
  private
  
  def parse_csp_violation(raw_post)
    return nil if raw_post.blank?
    
    json_data = JSON.parse(raw_post)
    
    # CSP reports come in a 'csp-report' wrapper
    report = json_data['csp-report']
    return nil unless report.is_a?(Hash)
    
    # Validate required fields
    required_fields = ['blocked-uri', 'document-uri', 'violated-directive']
    return nil unless required_fields.all? { |field| report[field].present? }
    
    report
  rescue JSON::ParserError
    nil
  end
end