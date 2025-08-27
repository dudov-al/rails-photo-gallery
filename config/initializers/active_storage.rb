# Configure Active Storage for high-volume image processing

# Use libvips for faster image processing
Rails.application.config.active_storage.variant_processor = :vips

# Precompile assets for Active Storage
Rails.application.config.assets.precompile += %w[activestorage.js]

# Configure maximum file size
Rails.application.config.active_storage.max_file_size = 50.megabytes

# Configure content types that can be served inline
Rails.application.config.active_storage.content_types_allowed_inline += %w[
  image/png
  image/jpeg
  image/jpg
  image/gif
  image/webp
  image/heic
  image/heif
]

# Configure content types to always serve as attachment
Rails.application.config.active_storage.content_types_to_serve_as_binary += %w[
  image/svg+xml
]

# Resolve N+1 queries in development
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy_path if Rails.env.development?

# Configure video processing (optional for future use)
Rails.application.config.active_storage.video_preview_arguments = [
  "-vf", "scale=800:600>",
  "-frames:v", "1",
  "-f", "image2",
  "-c:v", "png"
]

# Configure image analysis
Rails.application.config.active_storage.analyzers = [
  ActiveStorage::Analyzer::ImageAnalyzer::Vips,
  ActiveStorage::Analyzer::ImageAnalyzer::ImageMagick,
  ActiveStorage::Analyzer::VideoAnalyzer
]

# Configure previewers
Rails.application.config.active_storage.previewers = [
  ActiveStorage::Previewer::PopplerPDFPreviewer,
  ActiveStorage::Previewer::MuPDFPreviewer,
  ActiveStorage::Previewer::VideoPreviewer
]