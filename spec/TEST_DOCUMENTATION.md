# Test Suite Documentation

## Overview

This comprehensive test suite provides production-ready testing coverage for the Rails photo gallery application, ensuring stability, security, and correctness before final deployment.

## Test Coverage

### 1. Model Tests (`spec/models/`)

**Photographer Model** (`photographer_spec.rb`)
- Authentication and security features
- Password strength validation
- Account lockout mechanisms
- Security event logging
- Email validation and normalization
- Failed attempt tracking

**Gallery Model** (`gallery_spec.rb`)
- CRUD operations and validations
- Slug generation and uniqueness
- Password protection features
- Publication status management
- Expiration handling
- Security auditing

**Image Model** (`image_spec.rb`)
- File attachment and validation
- Processing status management
- Variant generation and caching
- Metadata extraction
- Security validations
- Performance optimization

**SecurityEvent Model** (`security_event_spec.rb`)
- Audit trail functionality
- Event categorization and analysis
- IP-based tracking
- Attack pattern detection
- Security reporting

### 2. Controller Tests (`spec/controllers/`)

**SessionsController** (`sessions_controller_spec.rb`)
- Login and logout functionality
- Session security and timeout
- Rate limiting and brute force protection
- Security event logging

**PhotographersController** (`photographers_controller_spec.rb`)
- User registration and validation
- Input sanitization
- Security measures during signup

**GalleriesController** (`galleries_controller_spec.rb`)
- CRUD operations with authorization
- Gallery management workflows
- Performance optimization
- Security controls

**ImagesController** (`images_controller_spec.rb`)
- File upload security and validation
- Bulk operations
- Authorization controls
- Error handling

**PublicGalleriesController** (`public_galleries_controller_spec.rb`)
- Public gallery viewing
- Password authentication
- Performance optimization
- Cache management

### 3. Integration Tests (`spec/integration/`)

**User Registration Flow** (`user_registration_flow_spec.rb`)
- End-to-end registration process
- Security validations
- Error handling
- Mobile compatibility

**Gallery Management Flow** (`gallery_management_flow_spec.rb`)
- Complete gallery lifecycle
- Image upload workflows
- Gallery editing and management
- Access control verification

**Public Gallery Viewing** (`public_gallery_viewing_spec.rb`)
- Anonymous gallery access
- Password protection flows
- Performance optimization
- Security measures

**Authentication Flow** (`authentication_flow_spec.rb`)
- Login/logout processes
- Session management
- Security controls
- Error handling

### 4. Security Tests (`spec/security/`)

**Authentication Security** (`authentication_security_spec.rb`)
- Session fixation prevention
- Account lockout mechanisms
- Rate limiting
- Input validation
- Concurrent access protection
- Security headers
- Error handling

**File Security** (`file_security_spec.rb`)
- Malicious file detection
- File type validation
- Size limitations
- Content scanning
- Path traversal prevention

**Comprehensive Security** (`comprehensive_security_spec.rb`)
- XSS protection
- CSRF protection  
- SQL injection prevention
- Path traversal protection
- Session security
- Rate limiting and DoS protection
- Content Security Policy
- Security headers
- Authentication bypass prevention
- Data exposure prevention
- Input validation and sanitization
- Cryptographic security

## Test Configuration

### RSpec Configuration (`spec/rails_helper.rb`)
- Database cleaner setup
- FactoryBot integration
- ActiveStorage test configuration
- Redis/Cache testing
- Security helpers inclusion
- Background job testing

### Factory Definitions (`spec/factories/`)
- **photographers.rb**: User factories with various states
- **galleries.rb**: Gallery factories with different configurations
- **images.rb**: Image factories with file attachments
- **security_events.rb**: Security event factories for testing

### Test Helpers (`spec/support/`)

**Security Helpers** (`security_helpers.rb`)
- Authentication helpers
- Gallery password authentication
- Malicious file creation
- Rate limiting simulation
- Security event expectations

**Active Storage Helpers** (`active_storage_helpers.rb`)
- File creation utilities
- Image processing mocking
- Upload testing helpers

**Redis Helpers** (`redis_helpers.rb`)
- Cache testing utilities
- Redis mocking
- Rate limiting helpers

**Shared Examples** (`shared_examples.rb`)
- Reusable test patterns
- Security test templates
- Validation helpers
- Common behavior tests

**Test Utilities** (`test_utilities.rb`)
- Performance testing helpers
- Security attack simulation
- Concurrency testing
- Memory and timing utilities

## Running Tests

### Full Test Suite
```bash
bundle exec rspec
```

### Specific Test Categories
```bash
# Model tests
bundle exec rspec spec/models/

# Controller tests  
bundle exec rspec spec/controllers/

# Integration tests
bundle exec rspec spec/integration/

# Security tests
bundle exec rspec spec/security/
```

### Individual Test Files
```bash
# Run specific test file
bundle exec rspec spec/models/photographer_spec.rb

# Run specific test with line number
bundle exec rspec spec/models/photographer_spec.rb:45
```

### Test with Coverage
```bash
# With SimpleCov (if configured)
COVERAGE=true bundle exec rspec
```

## Test Environment Setup

### Prerequisites
1. PostgreSQL database for testing
2. Redis server (for rate limiting tests)
3. ImageMagick or similar (for image processing)
4. Required gems installed (`bundle install`)

### Configuration
```bash
# Set up test database
bin/rails db:create RAILS_ENV=test
bin/rails db:migrate RAILS_ENV=test

# Clear test data
bin/rails db:test:prepare
```

### Environment Variables
- `RAILS_ENV=test` - Ensures test environment
- `COVERAGE=true` - Enables coverage reporting
- `PARALLEL_WORKERS=4` - For parallel test execution

## Security Testing Features

### Authentication & Authorization
- Session security and timeout
- Account lockout mechanisms
- Rate limiting and brute force protection
- CSRF protection
- Authentication bypass prevention

### File Upload Security
- Malicious file type detection
- File size validation
- Content type verification
- Path traversal prevention
- Virus signature detection

### Input Validation
- XSS prevention
- SQL injection protection
- Input sanitization
- Parameter validation
- Malformed request handling

### Performance & DoS Protection
- Rate limiting enforcement
- Concurrent request handling
- Memory usage monitoring
- Response time validation
- Query count optimization

## Continuous Integration

### GitHub Actions Example
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:6
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v2
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Setup Database
        run: |
          bin/rails db:create RAILS_ENV=test
          bin/rails db:migrate RAILS_ENV=test
      - name: Run Tests
        run: bundle exec rspec
      - name: Upload Coverage
        uses: codecov/codecov-action@v1
```

## Test Maintenance

### Adding New Tests
1. Follow existing patterns and conventions
2. Use appropriate factories and helpers
3. Include security considerations
4. Add integration tests for new features
5. Update documentation as needed

### Performance Considerations
- Use database transactions for faster tests
- Mock external services appropriately
- Avoid unnecessary database queries
- Clean up test data efficiently

### Security Test Updates
- Review security tests with each new feature
- Add tests for new attack vectors
- Validate input sanitization
- Test authorization controls

## Coverage Goals

### Minimum Coverage Targets
- **Model Tests**: 95% line coverage
- **Controller Tests**: 90% line coverage  
- **Integration Tests**: 85% critical path coverage
- **Security Tests**: 100% security feature coverage

### Key Metrics
- All critical user flows tested
- All security features validated
- Error handling scenarios covered
- Performance requirements verified

## Troubleshooting

### Common Issues

**Database Connection Errors**
```bash
# Reset test database
bin/rails db:drop db:create db:migrate RAILS_ENV=test
```

**Redis Connection Issues**
```bash
# Start Redis server
redis-server
# Or use Docker
docker run -p 6379:6379 redis:6
```

**File Upload Test Failures**
```bash
# Clear ActiveStorage test files
rm -rf tmp/storage/
```

**Slow Tests**
- Check for N+1 queries
- Mock external service calls
- Use database transactions
- Optimize factory usage

This comprehensive test suite ensures the photo gallery application meets production-quality standards for functionality, security, and performance.