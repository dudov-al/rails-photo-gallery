FactoryBot.define do
  factory :gallery do
    association :photographer
    sequence(:title) { |n| "Gallery #{n}" }
    description { "A beautiful photo gallery showcasing various moments and memories." }
    published { false }
    featured { false }
    password { nil }
    password_confirmation { nil }
    expires_at { nil }
    views_count { 0 }
    images_count { 0 }

    # Auto-generate slug from title
    before(:create) do |gallery|
      if gallery.slug.blank?
        base_slug = gallery.title.parameterize
        counter = 1
        candidate_slug = base_slug
        
        while Gallery.exists?(slug: candidate_slug)
          candidate_slug = "#{base_slug}-#{counter}"
          counter += 1
        end
        
        gallery.slug = candidate_slug
      end
    end

    trait :published do
      published { true }
    end

    trait :unpublished do
      published { false }
    end

    trait :featured do
      published { true }
      featured { true }
    end

    trait :password_protected do
      password { "GalleryPassword123!" }
      password_confirmation { "GalleryPassword123!" }
    end

    trait :with_weak_password do
      password { "password123" }
      password_confirmation { "password123" }
    end

    trait :with_strong_password do
      password { "SuperSecure&GalleryPassword123!" }
      password_confirmation { "SuperSecure&GalleryPassword123!" }
    end

    trait :expired do
      published { true }
      expires_at { 1.day.ago }
    end

    trait :expiring_soon do
      published { true }
      expires_at { 2.hours.from_now }
    end

    trait :with_future_expiration do
      published { true }
      expires_at { 1.month.from_now }
    end

    trait :with_views do
      views_count { rand(50..500) }
    end

    trait :with_images do
      after(:create) do |gallery|
        create_list(:image, 5, gallery: gallery)
        gallery.update_column(:images_count, gallery.images.count)
      end
    end

    trait :with_many_images do
      after(:create) do |gallery|
        create_list(:image, 20, gallery: gallery)
        gallery.update_column(:images_count, gallery.images.count)
      end
    end

    trait :empty do
      # No images, explicitly ensure images_count is 0
      images_count { 0 }
    end

    # Custom slug for testing
    trait :with_custom_slug do
      slug { 'custom-gallery-slug' }
    end

    # For testing password complexity validation
    trait :with_dictionary_word_password do
      password { "gallery123" }
      password_confirmation { "gallery123" }
    end

    trait :with_repeated_chars_password do
      password { "aaabbbccc123" }
      password_confirmation { "aaabbbccc123" }
    end

    # For testing edge cases
    trait :with_long_title do
      title { "A" * 300 } # Over the 255 character limit
    end

    trait :with_special_chars_title do
      title { "Gallery with Special Characters: @#$%^&*()" }
    end
  end
end