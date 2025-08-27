import { Controller } from "@hotwired/stimulus"

// Enhanced authentication form controller with accessibility and UX improvements
export default class extends Controller {
  static targets = [
    "form", "submitButton", "alerts", 
    "emailField", "passwordField", "passwordToggle",
    "nameField", "passwordConfirmationField", "passwordConfirmationToggle",
    "passwordStrength", "passwordStrengthFill", "passwordStrengthText",
    "termsAgreement", "rememberDevice"
  ]

  connect() {
    this.setupFormValidation()
    this.setupProgressiveEnhancement()
    this.attemptCount = 0
    this.rateLimitActive = false
  }

  // Handle form submission with enhanced UX
  handleSubmit(event) {
    if (this.rateLimitActive) {
      event.preventDefault()
      this.showAlert('Rate limit active. Please wait before trying again.', 'warning')
      return
    }

    this.setLoadingState(true)
    this.clearAlerts()
    this.attemptCount++

    // Add rate limiting after multiple attempts
    if (this.attemptCount >= 3) {
      this.activateRateLimit()
    }
  }

  // Toggle password visibility with accessibility
  togglePasswordVisibility(event) {
    const toggle = event.currentTarget
    const isPasswordConfirmation = toggle.hasAttribute('data-auth-form-target') && 
                                   toggle.getAttribute('data-auth-form-target').includes('passwordConfirmationToggle')
    
    const field = isPasswordConfirmation ? this.passwordConfirmationFieldTarget : this.passwordFieldTarget
    const icon = toggle.querySelector('svg')
    
    if (field.type === 'password') {
      field.type = 'text'
      toggle.setAttribute('aria-label', 'Hide password')
      icon.innerHTML = `
        <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19M1 1l22 22"/>
        <path d="M9 9.5a3 3 0 1 0 4.5 4.5"/>
      `
    } else {
      field.type = 'password'
      toggle.setAttribute('aria-label', 'Show password')
      icon.innerHTML = `
        <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
        <circle cx="12" cy="12" r="3"/>
      `
    }

    // Maintain focus on the password field
    field.focus()
  }

  // Clear field-specific errors when user starts typing
  clearFieldError(event) {
    const field = event.target
    field.classList.remove('is-invalid')
    
    const errorElement = field.parentElement.querySelector('.invalid-feedback')
    if (errorElement) {
      errorElement.remove()
    }
  }

  // Handle "forgot password" functionality
  handleForgotPassword(event) {
    event.preventDefault()
    
    this.showAlert(
      'Password reset functionality will be available soon. Please contact support for assistance.',
      'info'
    )
  }

  // Check password strength for registration
  checkPasswordStrength(event) {
    if (!this.hasPasswordStrengthTarget) return
    
    const password = event.target.value
    const strength = this.calculatePasswordStrength(password)
    
    if (password.length > 0) {
      this.passwordStrengthTarget.style.display = 'block'
      this.updateStrengthDisplay(strength)
    } else {
      this.passwordStrengthTarget.style.display = 'none'
    }
  }

  // Check password confirmation matching
  checkPasswordMatch(event) {
    if (!this.hasPasswordFieldTarget || !this.hasPasswordConfirmationFieldTarget) return
    
    const password = this.passwordFieldTarget.value
    const confirmation = event.target.value
    
    if (confirmation.length > 0) {
      if (password === confirmation) {
        event.target.classList.remove('is-invalid')
        event.target.classList.add('is-valid')
      } else {
        event.target.classList.remove('is-valid')
        event.target.classList.add('is-invalid')
      }
    } else {
      event.target.classList.remove('is-valid', 'is-invalid')
    }
  }

  calculatePasswordStrength(password) {
    let score = 0
    const checks = {
      length: password.length >= 8,
      lowercase: /[a-z]/.test(password),
      uppercase: /[A-Z]/.test(password),
      number: /\d/.test(password),
      special: /[^a-zA-Z\d]/.test(password),
      longLength: password.length >= 12
    }
    
    Object.values(checks).forEach(check => {
      if (check) score++
    })
    
    return {
      score: score,
      checks: checks
    }
  }

  updateStrengthDisplay(strength) {
    if (!this.hasPasswordStrengthFillTarget || !this.hasPasswordStrengthTextTarget) return
    
    const percentage = (strength.score / 6) * 100
    let level = 'weak'
    let color = '#e74c3c'
    
    if (strength.score >= 4) {
      level = 'strong'
      color = '#27ae60'
    } else if (strength.score >= 3) {
      level = 'good'
      color = '#f39c12'
    }
    
    this.passwordStrengthFillTarget.style.width = percentage + '%'
    this.passwordStrengthFillTarget.style.backgroundColor = color
    
    this.passwordStrengthTextTarget.textContent = `Password strength: ${level}`
    this.passwordStrengthTextTarget.style.color = color
  }

  // Enhanced loading states with accessibility
  setLoadingState(loading) {
    const button = this.submitButtonTarget
    const form = this.formTarget
    
    if (loading) {
      button.disabled = true
      button.setAttribute('aria-busy', 'true')
      button.innerHTML = `
        <span class="btn-spinner" aria-hidden="true"></span>
        Signing in...
      `
      form.classList.add('form-loading')
    } else {
      button.disabled = false
      button.setAttribute('aria-busy', 'false')
      button.innerHTML = 'Sign In'
      form.classList.remove('form-loading')
    }
  }

  // Show alerts with proper accessibility
  showAlert(message, type = 'error') {
    const alerts = this.alertsTarget
    const alertClass = type === 'error' ? 'alert-error' : 
                     type === 'warning' ? 'alert-warning' : 'alert-info'
    
    alerts.innerHTML = `
      <div class="auth-alert ${alertClass}" role="alert" aria-live="assertive">
        <div class="alert-icon" aria-hidden="true">
          ${this.getAlertIcon(type)}
        </div>
        <div class="alert-content">
          <p class="alert-message">${message}</p>
        </div>
        <button type="button" 
                class="alert-close" 
                data-action="click->auth-form#dismissAlert"
                aria-label="Dismiss alert">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" aria-hidden="true">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>
      </div>
    `

    // Auto-dismiss non-error alerts
    if (type !== 'error') {
      setTimeout(() => this.clearAlerts(), 5000)
    }
  }

  clearAlerts() {
    this.alertsTarget.innerHTML = ''
  }

  dismissAlert() {
    this.clearAlerts()
  }

  // Rate limiting functionality
  activateRateLimit() {
    this.rateLimitActive = true
    this.setLoadingState(false)
    
    setTimeout(() => {
      this.rateLimitActive = false
    }, 10000) // 10 second rate limit
  }

  // Progressive enhancement setup
  setupProgressiveEnhancement() {
    // Auto-focus email field if empty
    if (this.hasEmailFieldTarget && !this.emailFieldTarget.value) {
      setTimeout(() => this.emailFieldTarget.focus(), 100)
    }

    // Enhanced keyboard navigation
    this.formTarget.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        const activeElement = document.activeElement
        if (activeElement === this.emailFieldTarget) {
          event.preventDefault()
          this.passwordFieldTarget.focus()
        }
      }
    })
  }

  // Form validation setup
  setupFormValidation() {
    // Real-time email validation
    if (this.hasEmailFieldTarget) {
      this.emailFieldTarget.addEventListener('blur', () => {
        this.validateEmail()
      })
    }

    // Password strength indicator (subtle)
    if (this.hasPasswordFieldTarget) {
      this.passwordFieldTarget.addEventListener('input', () => {
        this.validatePassword()
      })
    }
  }

  validateEmail() {
    const email = this.emailFieldTarget.value.trim()
    const isValid = email.match(/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    
    if (email && !isValid) {
      this.emailFieldTarget.classList.add('is-invalid')
      this.showFieldError(this.emailFieldTarget, 'Please enter a valid email address')
    }
  }

  validatePassword() {
    const password = this.passwordFieldTarget.value
    
    // Only show validation if user has started typing
    if (password.length > 0 && password.length < 6) {
      this.passwordFieldTarget.classList.add('is-invalid')
    }
  }

  showFieldError(field, message) {
    const existingError = field.parentElement.querySelector('.invalid-feedback')
    if (!existingError) {
      const errorDiv = document.createElement('div')
      errorDiv.className = 'invalid-feedback'
      errorDiv.setAttribute('role', 'alert')
      errorDiv.textContent = message
      field.parentElement.appendChild(errorDiv)
    }
  }

  getAlertIcon(type) {
    switch (type) {
      case 'error':
        return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <circle cx="12" cy="12" r="10"/>
                  <line x1="15" y1="9" x2="9" y2="15"/>
                  <line x1="9" y1="9" x2="15" y2="15"/>
                </svg>`
      case 'warning':
        return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
                  <line x1="12" y1="9" x2="12" y2="13"/>
                  <line x1="12" y1="17" x2="12.01" y2="17"/>
                </svg>`
      default:
        return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <circle cx="12" cy="12" r="10"/>
                  <path d="m9 12 2 2 4-4"/>
                </svg>`
    }
  }
}