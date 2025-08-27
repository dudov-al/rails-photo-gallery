FactoryBot.define do
  factory :security_event do
    association :photographer, factory: :photographer, strategy: :build
    event_type { "successful_login" }
    ip_address { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) WebKit/537.36" }
    severity { "LOW" }
    occurred_at { Time.current }
    additional_data { {} }
    request_path { "/login" }
    session_id { SecureRandom.hex(16) }

    trait :failed_login do
      event_type { "failed_login_attempt" }
      severity { "MEDIUM" }
      additional_data do
        {
          "email" => photographer&.email || "test@example.com",
          "failed_attempts" => 1,
          "reason" => "incorrect_password"
        }
      end
    end

    trait :account_locked do
      event_type { "account_locked" }
      severity { "HIGH" }
      additional_data do
        {
          "email" => photographer&.email || "test@example.com",
          "failed_attempts" => 5,
          "locked_until" => 30.minutes.from_now.iso8601
        }
      end
    end

    trait :gallery_auth_success do
      event_type { "gallery_auth_success" }
      severity { "LOW" }
      request_path { "/g/sample-gallery/auth" }
      additional_data do
        {
          "gallery_id" => 1,
          "gallery_slug" => "sample-gallery"
        }
      end
    end

    trait :gallery_auth_failed do
      event_type { "gallery_auth_failed" }
      severity { "MEDIUM" }
      request_path { "/g/sample-gallery/auth" }
      additional_data do
        {
          "gallery_id" => 1,
          "gallery_slug" => "sample-gallery",
          "attempts" => 3
        }
      end
    end

    trait :gallery_auth_blocked do
      event_type { "gallery_auth_blocked" }
      severity { "HIGH" }
      request_path { "/g/sample-gallery/auth" }
      additional_data do
        {
          "gallery_id" => 1,
          "gallery_slug" => "sample-gallery",
          "attempts" => 10,
          "reason" => "too_many_attempts"
        }
      end
    end

    trait :suspicious_activity do
      event_type { "suspicious_activity" }
      severity { "HIGH" }
      additional_data do
        {
          "reason" => "multiple_failed_logins",
          "pattern_detected" => "brute_force",
          "attempts_count" => 15
        }
      end
    end

    trait :file_upload_blocked do
      event_type { "file_upload_blocked" }
      severity { "MEDIUM" }
      request_path { "/images" }
      additional_data do
        {
          "filename" => "malicious.php",
          "content_type" => "application/x-php",
          "reason" => "invalid_file_type",
          "file_size" => 1024
        }
      end
    end

    trait :session_hijack_attempt do
      event_type { "session_hijack_attempt" }
      severity { "CRITICAL" }
      additional_data do
        {
          "original_ip" => "127.0.0.1",
          "new_ip" => "192.168.1.100",
          "original_user_agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
          "new_user_agent" => "curl/7.64.1",
          "session_age" => "1 hour"
        }
      end
    end

    trait :csp_violation do
      event_type { "csp_violation" }
      severity { "MEDIUM" }
      request_path { "/csp-report" }
      additional_data do
        {
          "violated_directive" => "script-src",
          "blocked_uri" => "https://evil.com/script.js",
          "document_uri" => "https://example.com/gallery",
          "referrer" => "https://example.com/login"
        }
      end
    end

    trait :rate_limit_exceeded do
      event_type { "rate_limit_exceeded" }
      severity { "MEDIUM" }
      additional_data do
        {
          "limit_type" => "login_attempts",
          "limit" => 5,
          "window" => "5 minutes",
          "requests_count" => 10
        }
      end
    end

    trait :account_created do
      event_type { "account_created" }
      severity { "LOW" }
      request_path { "/photographers" }
      additional_data do
        {
          "email" => photographer&.email || "new_user@example.com",
          "registration_method" => "form"
        }
      end
    end

    # Severity level traits
    trait :low_severity do
      severity { "LOW" }
    end

    trait :medium_severity do
      severity { "MEDIUM" }
    end

    trait :high_severity do
      severity { "HIGH" }
    end

    trait :critical_severity do
      severity { "CRITICAL" }
    end

    # IP address variants for testing
    trait :from_localhost do
      ip_address { "127.0.0.1" }
    end

    trait :from_private_network do
      ip_address { "192.168.1.100" }
    end

    trait :from_public_ip do
      ip_address { "203.0.113.1" }
    end

    trait :from_suspicious_ip do
      ip_address { "198.51.100.1" }
    end

    # Time-based traits
    trait :recent do
      occurred_at { 5.minutes.ago }
    end

    trait :old do
      occurred_at { 1.week.ago }
    end

    trait :very_old do
      occurred_at { 1.month.ago }
    end

    # Without photographer association for anonymous events
    trait :anonymous do
      photographer { nil }
    end

    # User agent variations
    trait :mobile_user_agent do
      user_agent { "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15" }
    end

    trait :bot_user_agent do
      user_agent { "Googlebot/2.1 (+http://www.google.com/bot.html)" }
    end

    trait :suspicious_user_agent do
      user_agent { "curl/7.64.1" }
    end

    # Bulk creation helpers
    factory :security_event_with_rich_data do
      additional_data do
        {
          "request_method" => "POST",
          "request_headers" => {
            "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language" => "en-US,en;q=0.5",
            "Accept-Encoding" => "gzip, deflate"
          },
          "response_status" => 200,
          "processing_time" => 0.125,
          "database_queries" => 3
        }
      end
    end
  end
end