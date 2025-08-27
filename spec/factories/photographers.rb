FactoryBot.define do
  factory :photographer do
    sequence(:email) { |n| "photographer#{n}@example.com" }
    sequence(:name) { |n| "Photographer #{n}" }
    password { "SecurePassword123!" }
    password_confirmation { "SecurePassword123!" }
    active { true }
    failed_attempts { 0 }
    locked_until { nil }
    last_failed_attempt { nil }
    last_login_at { nil }
    last_login_ip { nil }

    trait :inactive do
      active { false }
    end

    trait :locked do
      failed_attempts { 5 }
      locked_until { 30.minutes.from_now }
      last_failed_attempt { 1.minute.ago }
    end

    trait :with_failed_attempts do
      failed_attempts { 3 }
      last_failed_attempt { 5.minutes.ago }
    end

    trait :recently_logged_in do
      last_login_at { 1.hour.ago }
      last_login_ip { '127.0.0.1' }
      failed_attempts { 0 }
    end

    trait :with_galleries do
      after(:create) do |photographer|
        create_list(:gallery, 3, photographer: photographer)
      end
    end

    trait :with_published_galleries do
      after(:create) do |photographer|
        create_list(:gallery, 2, :published, photographer: photographer)
        create(:gallery, :unpublished, photographer: photographer)
      end
    end

    # Weak password for testing validation
    trait :with_weak_password do
      password { "password123" }
      password_confirmation { "password123" }
    end

    # Strong password for security tests
    trait :with_strong_password do
      password { "VerySecure&ComplexPassword123!" }
      password_confirmation { "VerySecure&ComplexPassword123!" }
    end
  end
end