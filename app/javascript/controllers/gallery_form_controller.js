import { Controller } from "@hotwired/stimulus"

// Gallery form controller for enhanced UX and validation
export default class extends Controller {
  static targets = [
    "passwordFields", "expirationFields", "form", "titleField", 
    "descriptionField", "publishedCheckbox", "passwordStrengthIndicator"
  ]

  static values = {
    isEditing: Boolean
  }

  connect() {
    this.setupFormEnhancements()
    this.setupValidation()
    this.setupAutoSave()
    
    // Initialize form state
    this.updatePasswordFieldsVisibility()
    this.updateExpirationFieldsVisibility()
    
    console.log("Gallery form controller connected", {
      isEditing: this.isEditingValue
    })
  }

  disconnect() {
    this.clearAutoSaveTimer()
  }

  // Toggle password protection fields
  togglePasswordProtection(event) {
    const isEnabled = event.target.checked
    this.updatePasswordFieldsVisibility(isEnabled)
    
    if (isEnabled) {
      this.focusPasswordField()
      this.showPasswordTips()
    } else {
      this.clearPasswordFields()
      this.hidePasswordTips()
    }
  }

  // Toggle expiration date fields
  toggleExpiration(event) {
    const isEnabled = event.target.checked
    this.updateExpirationFieldsVisibility(isEnabled)
    
    if (isEnabled) {
      this.setDefaultExpirationDate()
      this.focusExpirationField()
    } else {
      this.clearExpirationFields()
    }
  }

  // Handle published state changes
  togglePublishedState(event) {
    const isPublished = event.target.checked
    
    if (isPublished) {
      this.showPublishWarning()
    }
    
    // Update preview if available
    this.updateGalleryPreview()
  }

  // Form submission handler
  handleSubmit(event) {
    this.clearAutoSaveTimer()
    
    if (!this.validateForm()) {
      event.preventDefault()
      this.showValidationErrors()
      return
    }
    
    this.setSubmittingState(true)
    this.clearFormDraft()
  }

  // Password strength checking (integrated with auth form controller)
  checkPasswordStrength(event) {
    const password = event.target.value
    
    if (this.hasPasswordStrengthIndicatorTarget) {
      const strength = this.calculatePasswordStrength(password)
      this.updatePasswordStrengthDisplay(strength)
    }
  }

  // Private methods
  setupFormEnhancements() {
    // Auto-resize description textarea
    if (this.hasDescriptionFieldTarget) {
      this.setupTextareaAutoResize(this.descriptionFieldTarget)
    }
    
    // Character count for title
    if (this.hasTitleFieldTarget) {
      this.setupCharacterCount(this.titleFieldTarget, 255)
    }
    
    // Enhanced keyboard navigation
    this.setupKeyboardNavigation()
    
    // Prevent accidental navigation away
    this.setupUnloadProtection()
  }

  setupValidation() {
    // Real-time validation for required fields
    if (this.hasTitleFieldTarget) {
      this.titleFieldTarget.addEventListener('blur', () => {
        this.validateTitle()
      })
    }
    
    // Password validation
    const passwordFields = this.element.querySelectorAll('input[type="password"]')
    passwordFields.forEach(field => {
      field.addEventListener('input', () => {
        this.validatePasswords()
      })
    })
  }

  setupAutoSave() {
    if (this.isEditingValue) {
      this.autoSaveTimer = null
      const inputs = this.element.querySelectorAll('input, textarea, select')
      
      inputs.forEach(input => {
        input.addEventListener('input', () => {
          this.scheduleAutoSave()
        })
      })
    }
  }

  scheduleAutoSave() {
    this.clearAutoSaveTimer()
    this.autoSaveTimer = setTimeout(() => {
      this.saveFormDraft()
    }, 3000) // Save after 3 seconds of inactivity
  }

  clearAutoSaveTimer() {
    if (this.autoSaveTimer) {
      clearTimeout(this.autoSaveTimer)
      this.autoSaveTimer = null
    }
  }

  saveFormDraft() {
    if (!this.hasFormTarget) return
    
    try {
      const formData = new FormData(this.formTarget)
      const draftData = Object.fromEntries(formData.entries())
      
      // Save to localStorage with gallery ID
      const galleryId = this.element.dataset.galleryId || 'new'
      localStorage.setItem(`gallery_draft_${galleryId}`, JSON.stringify({
        data: draftData,
        timestamp: Date.now()
      }))
      
      this.showAutoSaveIndicator()
    } catch (error) {
      console.warn('Auto-save failed:', error)
    }
  }

  clearFormDraft() {
    const galleryId = this.element.dataset.galleryId || 'new'
    localStorage.removeItem(`gallery_draft_${galleryId}`)
  }

  updatePasswordFieldsVisibility(forceShow = null) {
    if (!this.hasPasswordFieldsTarget) return
    
    const checkbox = this.element.querySelector('#enable-password')
    const isVisible = forceShow !== null ? forceShow : checkbox?.checked
    
    this.passwordFieldsTarget.style.display = isVisible ? 'block' : 'none'
    
    if (isVisible) {
      this.passwordFieldsTarget.setAttribute('aria-hidden', 'false')
    } else {
      this.passwordFieldsTarget.setAttribute('aria-hidden', 'true')
    }
  }

  updateExpirationFieldsVisibility(forceShow = null) {
    if (!this.hasExpirationFieldsTarget) return
    
    const checkbox = this.element.querySelector('#enable-expiration')
    const isVisible = forceShow !== null ? forceShow : checkbox?.checked
    
    this.expirationFieldsTarget.style.display = isVisible ? 'block' : 'none'
    
    if (isVisible) {
      this.expirationFieldsTarget.setAttribute('aria-hidden', 'false')
    } else {
      this.expirationFieldsTarget.setAttribute('aria-hidden', 'true')
    }
  }

  focusPasswordField() {
    const passwordField = this.passwordFieldsTarget?.querySelector('input[type="password"]')
    if (passwordField) {
      setTimeout(() => passwordField.focus(), 150)
    }
  }

  focusExpirationField() {
    const expirationField = this.expirationFieldsTarget?.querySelector('input[type="datetime-local"]')
    if (expirationField) {
      setTimeout(() => expirationField.focus(), 150)
    }
  }

  clearPasswordFields() {
    const passwordInputs = this.passwordFieldsTarget?.querySelectorAll('input[type="password"]')
    passwordInputs?.forEach(input => {
      input.value = ''
      input.classList.remove('is-valid', 'is-invalid')
    })
  }

  clearExpirationFields() {
    const expirationInput = this.expirationFieldsTarget?.querySelector('input[type="datetime-local"]')
    if (expirationInput) {
      expirationInput.value = ''
      expirationInput.classList.remove('is-valid', 'is-invalid')
    }
  }

  setDefaultExpirationDate() {
    const expirationInput = this.expirationFieldsTarget?.querySelector('input[type="datetime-local"]')
    if (expirationInput && !expirationInput.value) {
      const futureDate = new Date()
      futureDate.setDate(futureDate.getDate() + 30) // 30 days from now
      expirationInput.value = futureDate.toISOString().slice(0, 16)
    }
  }

  showPublishWarning() {
    const existingAlert = this.element.querySelector('.publish-warning-alert')
    if (existingAlert) return
    
    const alert = document.createElement('div')
    alert.className = 'alert alert-info alert-dismissible fade show publish-warning-alert'
    alert.innerHTML = `
      <div class="d-flex align-items-center">
        <svg class="me-2 flex-shrink-0" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor">
          <circle cx="12" cy="12" r="10"/>
          <path d="M12 6h.01"/>
          <path d="M12 12v6"/>
        </svg>
        <div class="flex-grow-1">
          <strong>Publishing Gallery:</strong> This gallery will be viewable by anyone with the link.
        </div>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
      </div>
    `
    
    this.formTarget.insertBefore(alert, this.formTarget.firstChild)
    
    // Auto-dismiss after 7 seconds
    setTimeout(() => {
      if (alert.parentNode) {
        alert.classList.remove('show')
        setTimeout(() => alert.remove(), 150)
      }
    }, 7000)
  }

  showPasswordTips() {
    // Could be expanded to show password tips in a tooltip or sidebar
  }

  hidePasswordTips() {
    // Clean up any password tip displays
  }

  validateForm() {
    let isValid = true
    
    // Validate title
    if (!this.validateTitle()) isValid = false
    
    // Validate passwords if enabled
    if (!this.validatePasswords()) isValid = false
    
    // Validate expiration date if enabled
    if (!this.validateExpirationDate()) isValid = false
    
    return isValid
  }

  validateTitle() {
    if (!this.hasTitleFieldTarget) return true
    
    const title = this.titleFieldTarget.value.trim()
    const isValid = title.length >= 1 && title.length <= 255
    
    this.updateFieldValidation(this.titleFieldTarget, isValid, 
      isValid ? null : 'Title must be between 1 and 255 characters')
    
    return isValid
  }

  validatePasswords() {
    const passwordField = this.element.querySelector('input[name="gallery[password]"]')
    const confirmField = this.element.querySelector('input[name="gallery[password_confirmation]"]')
    
    if (!passwordField || !confirmField) return true
    if (!passwordField.value && !confirmField.value) return true
    
    let isValid = true
    
    // Check password strength
    if (passwordField.value.length < 8) {
      this.updateFieldValidation(passwordField, false, 'Password must be at least 8 characters')
      isValid = false
    } else if (!this.isPasswordStrong(passwordField.value)) {
      this.updateFieldValidation(passwordField, false, 'Password must include uppercase, lowercase, and number')
      isValid = false
    } else {
      this.updateFieldValidation(passwordField, true)
    }
    
    // Check password confirmation
    if (passwordField.value !== confirmField.value) {
      this.updateFieldValidation(confirmField, false, 'Passwords do not match')
      isValid = false
    } else {
      this.updateFieldValidation(confirmField, true)
    }
    
    return isValid
  }

  validateExpirationDate() {
    const expirationField = this.element.querySelector('input[name="gallery[expires_at]"]')
    if (!expirationField || !expirationField.value) return true
    
    const selectedDate = new Date(expirationField.value)
    const now = new Date()
    const isValid = selectedDate > now
    
    this.updateFieldValidation(expirationField, isValid, 
      isValid ? null : 'Expiration date must be in the future')
    
    return isValid
  }

  updateFieldValidation(field, isValid, errorMessage = null) {
    field.classList.toggle('is-valid', isValid)
    field.classList.toggle('is-invalid', !isValid)
    
    // Remove existing error message
    const existingError = field.parentElement.querySelector('.invalid-feedback')
    if (existingError) {
      existingError.remove()
    }
    
    // Add new error message if needed
    if (!isValid && errorMessage) {
      const errorDiv = document.createElement('div')
      errorDiv.className = 'invalid-feedback'
      errorDiv.textContent = errorMessage
      field.parentElement.appendChild(errorDiv)
    }
  }

  isPasswordStrong(password) {
    return /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/.test(password)
  }

  calculatePasswordStrength(password) {
    let score = 0
    if (password.length >= 8) score++
    if (password.length >= 12) score++
    if (/[a-z]/.test(password)) score++
    if (/[A-Z]/.test(password)) score++
    if (/\d/.test(password)) score++
    if (/[^a-zA-Z\d]/.test(password)) score++
    
    return {
      score: score,
      level: score < 3 ? 'weak' : score < 5 ? 'good' : 'strong'
    }
  }

  updatePasswordStrengthDisplay(strength) {
    // This would integrate with the existing auth form controller
    // or implement similar functionality
  }

  setupTextareaAutoResize(textarea) {
    textarea.addEventListener('input', function() {
      this.style.height = 'auto'
      this.style.height = Math.min(this.scrollHeight, 200) + 'px'
    })
    
    // Initial resize
    textarea.style.height = 'auto'
    textarea.style.height = Math.min(textarea.scrollHeight, 200) + 'px'
  }

  setupCharacterCount(field, maxLength) {
    const countDisplay = document.createElement('div')
    countDisplay.className = 'character-count text-muted small mt-1'
    field.parentElement.appendChild(countDisplay)
    
    const updateCount = () => {
      const remaining = maxLength - field.value.length
      countDisplay.textContent = `${remaining} characters remaining`
      countDisplay.classList.toggle('text-warning', remaining < 50)
      countDisplay.classList.toggle('text-danger', remaining < 0)
    }
    
    field.addEventListener('input', updateCount)
    updateCount() // Initial count
  }

  setupKeyboardNavigation() {
    this.element.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && event.target.tagName !== 'TEXTAREA') {
        const formElements = Array.from(this.element.querySelectorAll(
          'input:not([type="hidden"]), textarea, select, button'
        )).filter(el => !el.disabled && el.offsetParent !== null)
        
        const currentIndex = formElements.indexOf(event.target)
        const nextElement = formElements[currentIndex + 1]
        
        if (nextElement) {
          event.preventDefault()
          nextElement.focus()
        }
      }
    })
  }

  setupUnloadProtection() {
    this.formChanged = false
    
    const inputs = this.element.querySelectorAll('input, textarea, select')
    inputs.forEach(input => {
      input.addEventListener('input', () => {
        this.formChanged = true
      })
    })
    
    window.addEventListener('beforeunload', (event) => {
      if (this.formChanged && !this.submitting) {
        event.preventDefault()
        event.returnValue = 'You have unsaved changes. Are you sure you want to leave?'
        return event.returnValue
      }
    })
  }

  setSubmittingState(submitting) {
    this.submitting = submitting
    this.formChanged = false
    
    if (submitting) {
      // Disable form elements
      const inputs = this.element.querySelectorAll('input, textarea, select, button')
      inputs.forEach(input => {
        if (!input.classList.contains('btn-outline-secondary')) {
          input.disabled = true
        }
      })
    }
  }

  showValidationErrors() {
    const firstInvalidField = this.element.querySelector('.is-invalid')
    if (firstInvalidField) {
      firstInvalidField.scrollIntoView({ behavior: 'smooth', block: 'center' })
      firstInvalidField.focus()
    }
  }

  showAutoSaveIndicator() {
    let indicator = document.querySelector('.auto-save-indicator')
    if (!indicator) {
      indicator = document.createElement('div')
      indicator.className = 'auto-save-indicator'
      indicator.innerHTML = `
        <small class="text-success">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <polyline points="20,6 9,17 4,12"/>
          </svg>
          Auto-saved
        </small>
      `
      indicator.style.cssText = `
        position: fixed; 
        top: 20px; 
        right: 20px; 
        background: rgba(255, 255, 255, 0.95); 
        padding: 8px 12px; 
        border-radius: 4px; 
        border: 1px solid rgba(40, 167, 69, 0.3);
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        transition: opacity 0.3s;
        z-index: 1050;
      `
      document.body.appendChild(indicator)
    }
    
    indicator.style.opacity = '1'
    setTimeout(() => {
      indicator.style.opacity = '0'
    }, 2000)
  }

  updateGalleryPreview() {
    // Placeholder for live preview functionality
    // Could update a preview pane or thumbnail
  }
}