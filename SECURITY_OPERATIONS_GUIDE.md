# Security Operations Guide
Professional Photo Gallery Platform

## Security Overview

This guide provides comprehensive security operations procedures for the photography platform, covering monitoring, incident response, and maintenance of security controls.

## Security Architecture

### Multi-Layer Defense Strategy

**Layer 1: Network Security**
- HTTPS enforcement with HSTS
- Content Security Policy (CSP)
- Rate limiting with distributed Redis backend
- IP-based access controls (optional)

**Layer 2: Authentication & Authorization**
- Bcrypt password hashing with complexity requirements
- Session-based authentication with regeneration
- Account lockout after failed attempts
- Gallery-level password protection

**Layer 3: Input Validation & Sanitization**
- File type validation with magic numbers
- XSS prevention with comprehensive sanitization
- SQL injection protection via parameterized queries
- Path traversal prevention

**Layer 4: Application Security**
- Secure file uploads with virus scanning
- Metadata stripping from images
- Encrypted storage with Vercel Blob
- CSRF protection on all forms

**Layer 5: Audit & Monitoring**
- Comprehensive security event logging
- Real-time threat detection
- Session hijacking detection
- Malicious file upload tracking

## Security Monitoring

### Security Event Types

**Authentication Events**
```ruby
# Critical events to monitor
- failed_login_attempt: Failed photographer login
- account_locked: Account locked after failed attempts
- session_hijack_attempt: Session security violation
- gallery_auth_failed: Failed gallery password attempt
- gallery_auth_blocked: Gallery brute force protection activated

# Success events for audit trail
- login_success: Successful photographer login
- gallery_auth_success: Successful gallery access
- password_changed: Password update events
```

**File Security Events**
```ruby
# File upload security
- file_upload_blocked: Malicious file detected
- virus_detected: Virus/malware content found
- metadata_stripped: EXIF data removed
- polyglot_file_detected: Multiple format signatures found

# File access security
- unauthorized_download: Access to protected file denied
- download_success: Successful file download logged
```

**Input Security Events**
```ruby
# Malicious input detection
- xss_attempt: Cross-site scripting detected
- sql_injection_attempt: SQL injection pattern found
- path_traversal_attempt: Directory traversal detected
- command_injection_attempt: System command injection detected
```

### Real-Time Monitoring Setup

**Log Monitoring Configuration**
```bash
# Monitor security log file
tail -f log/security_production.log | grep -E "(CRITICAL|HIGH)"

# Monitor specific security events
tail -f log/security_production.log | grep -E "(failed_login|account_locked|file_upload_blocked)"

# Monitor rate limiting events
tail -f log/production.log | grep "Rack::Attack"
```

**Alerting Thresholds**
```bash
# Critical Alerts (Immediate Response)
- 5+ failed_login_attempt from same IP in 5 minutes
- Any virus_detected event
- 10+ sql_injection_attempt in 1 hour
- 3+ account_locked events in 1 hour

# Warning Alerts (Monitor Closely)
- 20+ failed_login_attempt from different IPs in 1 hour
- 5+ file_upload_blocked events in 1 hour
- 10+ xss_attempt in 1 hour
```

### Security Dashboard Queries

**Failed Login Analysis**
```bash
# Count failed logins by IP
grep "failed_login_attempt" log/security_production.log | \
  grep -o '"ip_address":"[^"]*"' | sort | uniq -c | sort -nr

# Time-based failed login analysis
grep "failed_login_attempt" log/security_production.log | \
  grep "$(date +%Y-%m-%d)" | wc -l
```

**Gallery Security Analysis**
```bash
# Gallery brute force attempts
grep "gallery_auth_failed" log/security_production.log | \
  grep -o '"gallery_slug":"[^"]*"' | sort | uniq -c | sort -nr

# Blocked gallery access attempts
grep "gallery_auth_blocked" log/security_production.log | \
  grep "$(date +%Y-%m-%d)"
```

**File Security Analysis**
```bash
# Blocked file uploads
grep "file_upload_blocked" log/security_production.log | \
  grep -o '"reason":"[^"]*"' | sort | uniq -c

# Virus detection events
grep "virus_detected" log/security_production.log | \
  grep "$(date +%Y-%m-%d)"
```

## Incident Response Procedures

### Security Incident Classification

**CRITICAL (Immediate Response Required)**
- Active data breach or unauthorized access
- Virus/malware detection in uploaded files
- SQL injection attempts with database access
- Account takeover or session hijacking

**HIGH (Response within 1 hour)**
- Sustained brute force attacks
- Multiple account lockouts
- XSS attempts with potential impact
- Suspicious file upload patterns

**MEDIUM (Response within 4 hours)**
- Unusual authentication patterns
- Rate limiting threshold violations
- Failed security validations

**LOW (Response within 24 hours)**
- Single failed login attempts
- Normal security validations working
- Routine security log entries

### Incident Response Playbook

#### Phase 1: Detection & Assessment (0-15 minutes)

**1. Incident Detection**
```bash
# Check for active security events
grep -E "(CRITICAL|HIGH)" log/security_production.log | tail -20

# Identify affected resources
grep "$(date +%Y-%m-%d-%H)" log/security_production.log | \
  grep -o '"ip_address":"[^"]*"' | sort | uniq -c
```

**2. Initial Assessment**
```bash
# Determine incident scope
# - Single user affected or multiple?
# - Specific functionality or system-wide?
# - External attack or internal issue?

# Check system health
curl -s https://your-domain.com/health | jq
```

**3. Escalation Decision**
```bash
# Critical incidents: Immediate escalation
# High incidents: Notify security team
# Medium/Low: Log and monitor
```

#### Phase 2: Containment (15 minutes - 1 hour)

**1. Block Malicious Activity**
```bash
# Block IP address via rate limiting
# Add to Rack::Attack blocklist
# Update rate limiting rules if needed

# Example: Block IP in Rails console
Rails.cache.write("block_ip:#{malicious_ip}", true, expires_in: 24.hours)
```

**2. Protect Affected Accounts**
```bash
# Lock compromised accounts
photographer = Photographer.find_by(email: 'compromised@email.com')
photographer.update(locked_at: Time.current)

# Reset sessions for affected users
# Clear gallery sessions
Rails.cache.delete_matched("gallery_session:*")
```

**3. Isolate Affected Systems**
```bash
# If necessary, enable maintenance mode
export MAINTENANCE_MODE=true

# Disable specific functionality if needed
export DISABLE_UPLOADS=true
```

#### Phase 3: Investigation (1-4 hours)

**1. Evidence Collection**
```bash
# Extract security logs for timeframe
grep "$(date -d '1 hour ago' +%Y-%m-%d-%H)" log/security_production.log > incident_logs.txt

# Database forensics (if needed)
# Check for unauthorized data access
# Review audit trail for affected accounts
```

**2. Root Cause Analysis**
```bash
# Analyze attack pattern
# Identify vulnerability exploited
# Determine attack vector
# Assess potential data exposure
```

**3. Impact Assessment**
```bash
# Determine what data was accessed
# Identify affected users/galleries
# Calculate potential business impact
```

#### Phase 4: Eradication & Recovery (4-24 hours)

**1. Remove Threat**
```bash
# Apply security patches if needed
bundle update --conservative

# Update security configurations
# Strengthen affected security controls
```

**2. System Recovery**
```bash
# Restore affected accounts
photographer.update(locked_at: nil, failed_attempts: 0)

# Clear security blocks (if appropriate)
Rails.cache.delete("block_ip:#{ip_address}")

# Disable maintenance mode
export MAINTENANCE_MODE=false
```

**3. Security Enhancements**
```bash
# Implement additional security controls
# Update security policies
# Enhance monitoring rules
```

### Communication Procedures

**Internal Communication**
```bash
# Security Team Notification
Subject: [SECURITY] {{incident_classification}} - {{brief_description}}
- Incident type and severity
- Affected systems/users
- Initial containment actions
- Next steps and timeline

# Management Notification (Critical/High)
- Business impact assessment
- Customer communication requirements
- Legal/compliance implications
- Resource requirements
```

**External Communication**
```bash
# Customer Notification (if required)
- Transparent communication about impact
- Steps taken to resolve issue
- Recommendations for users
- Contact information for questions

# Regulatory Notification (if required)
- GDPR breach notification (if applicable)
- Industry-specific requirements
- Law enforcement (if criminal activity)
```

## Security Maintenance

### Daily Security Tasks

**1. Security Log Review (10 minutes)**
```bash
# Check overnight security events
grep "$(date -d 'yesterday' +%Y-%m-%d)" log/security_production.log | \
  grep -E "(CRITICAL|HIGH)" | wc -l

# Review failed authentication attempts
grep "failed_login_attempt" log/security_production.log | \
  grep "$(date +%Y-%m-%d)" | head -10
```

**2. System Health Check**
```bash
# Verify security services
curl -s https://your-domain.com/security-status | jq

# Check rate limiting functionality
redis-cli -u $REDIS_URL get "rack::attack:$(date +%s):login:/some-ip"
```

### Weekly Security Tasks

**1. Security Event Analysis (30 minutes)**
```bash
# Generate weekly security report
rails security:weekly_report

# Analyze security trends
# - Failed login patterns
# - File upload security events
# - Rate limiting effectiveness
```

**2. Access Review**
```bash
# Review photographer accounts
# Check for inactive accounts
# Verify account permissions
```

**3. Security Configuration Audit**
```bash
# Verify security headers
curl -I https://your-domain.com | grep -E "(CSP|HSTS|X-Frame)"

# Check SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com | \
  openssl x509 -noout -dates
```

### Monthly Security Tasks

**1. Comprehensive Security Audit (2 hours)**
```bash
# Run security test suite
bundle exec rspec spec/security/

# Dependency vulnerability scan
bundle audit
npm audit

# Configuration security review
rails security:audit_configuration
```

**2. Security Policy Review**
```bash
# Review and update security policies
# Update incident response procedures
# Review access controls and permissions
```

**3. Security Training**
```bash
# Review security incidents and lessons learned
# Update security documentation
# Team security awareness training
```

## Security Compliance

### Data Protection (GDPR/CCPA)

**Data Processing Inventory**
- **Personal Data**: Photographer emails, names, gallery metadata
- **Processing Purpose**: Gallery creation and management
- **Legal Basis**: Legitimate business interest
- **Retention Period**: Account deletion + 30 days
- **Security Measures**: Encryption, access controls, audit logging

**Data Subject Rights**
```bash
# Data export (Right to portability)
rails gdpr:export_data[photographer_id]

# Data deletion (Right to erasure)
rails gdpr:delete_account[photographer_id]

# Data rectification
# Standard update procedures through UI
```

### Security Controls Verification

**Access Controls**
- [ ] Multi-factor authentication available
- [ ] Account lockout mechanisms active
- [ ] Session management configured securely
- [ ] Gallery access controls functioning

**Data Protection**
- [ ] Encryption at rest enabled (Vercel Blob)
- [ ] Encryption in transit enforced (HTTPS)
- [ ] Secure file upload validation active
- [ ] Data backup encryption verified

**Monitoring & Logging**
- [ ] Security event logging active
- [ ] Log retention period configured
- [ ] Monitoring alerts configured
- [ ] Incident response procedures tested

## Security Tools & Scripts

### Security Monitoring Scripts

**Real-time Security Monitor**
```bash
#!/bin/bash
# security-monitor.sh
tail -f log/security_production.log | while read line; do
  if echo "$line" | grep -q "CRITICAL"; then
    echo "CRITICAL ALERT: $line" | mail -s "Security Alert" security@company.com
  fi
done
```

**Security Report Generator**
```bash
#!/bin/bash
# daily-security-report.sh
DATE=$(date +%Y-%m-%d)
echo "Security Report for $DATE"
echo "=========================="
echo "Failed Logins: $(grep "failed_login_attempt" log/security_production.log | grep "$DATE" | wc -l)"
echo "Account Lockouts: $(grep "account_locked" log/security_production.log | grep "$DATE" | wc -l)"
echo "Blocked Files: $(grep "file_upload_blocked" log/security_production.log | grep "$DATE" | wc -l)"
```

### Security Validation Commands

```bash
# Test rate limiting
rails security:test_rate_limiting

# Validate security headers
rails security:test_headers

# Test file upload security
rails security:test_file_validation

# Audit security configuration
rails security:audit_all
```

## Emergency Contacts

### Internal Security Team
```bash
# Primary Security Contact
Name: [Security Lead]
Email: security@company.com
Phone: [Emergency Number]
Escalation: 15 minutes

# Secondary Contact  
Name: [DevOps Lead]
Email: devops@company.com
Phone: [Emergency Number]
Escalation: 30 minutes

# Management Escalation
Name: [CTO/Technical Director]
Email: cto@company.com
Phone: [Emergency Number]
```

### External Security Resources
```bash
# Security Consultants
Company: [Security Firm]
Contact: [Consultant Name]
Phone: [Contact Number]

# Legal Counsel
Firm: [Law Firm]
Contact: [Attorney Name]
Phone: [Contact Number]

# Law Enforcement
Cyber Crime Unit: [Local Contact]
FBI IC3: https://www.ic3.gov
```

## Security Documentation

### Required Documentation
- [ ] Security policies and procedures
- [ ] Incident response playbook (this document)
- [ ] Risk assessment and treatment plans
- [ ] Security awareness training materials
- [ ] Compliance documentation
- [ ] Security architecture diagrams

### Documentation Maintenance
- **Quarterly Review**: Update procedures based on incidents
- **Annual Review**: Complete security policy review
- **Change Management**: Update docs with system changes
- **Version Control**: Maintain documentation in Git

## Success Metrics

### Security KPIs
- **Mean Time to Detection (MTTD)**: < 5 minutes for critical events
- **Mean Time to Response (MTTR)**: < 15 minutes for critical incidents
- **False Positive Rate**: < 5% for security alerts
- **Security Test Coverage**: > 95% of security controls tested
- **Incident Resolution**: 100% of incidents properly documented

### Security Health Indicators
- [ ] Zero unpatched critical vulnerabilities
- [ ] All security controls functioning correctly
- [ ] Security monitoring operational 24/7
- [ ] Incident response team trained and ready
- [ ] Regular security audits completed
- [ ] Compliance requirements met

The platform maintains enterprise-grade security operations with comprehensive monitoring, incident response, and maintenance procedures.