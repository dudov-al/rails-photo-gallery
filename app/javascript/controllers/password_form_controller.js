import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="password-form"
export default class extends Controller {
  static targets = ["form", "input", "error", "submit"]

  connect() {
    // Focus input after a short delay to ensure page is loaded
    setTimeout(() => {
      if (this.hasInputTarget) {
        this.inputTarget.focus()
      }
    }, 100)
  }

  submit(event) {
    event.preventDefault()
    
    const password = this.inputTarget.value.trim()
    
    if (!password) {
      this.showError('Please enter a password')
      return
    }

    this.setLoadingState(true)

    const formData = new FormData(this.formTarget)

    fetch(this.formTarget.action, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json, text/html'
      }
    })
    .then(response => {
      if (response.ok) {
        // Check if it's a redirect (successful authentication)
        if (response.redirected || response.status === 200) {
          this.showSuccess()
          // Redirect to the gallery
          setTimeout(() => {
            window.location.href = response.url || window.location.href.split('?')[0]
          }, 500)
        }
      } else if (response.status === 401) {
        // Unauthorized - wrong password
        return response.text().then(text => {
          // Try to parse as JSON first
          try {
            const data = JSON.parse(text)
            this.showError(data.error || 'Incorrect password')
          } catch {
            // If not JSON, show generic error
            this.showError('Incorrect password. Please try again.')
          }
        })
      } else {
        throw new Error('Unexpected response status: ' + response.status)
      }
    })
    .catch(error => {
      console.error('Password check error:', error)
      this.showError('An error occurred. Please try again.')
    })
    .finally(() => {
      this.setLoadingState(false)
    })
  }

  setLoadingState(loading) {
    this.submitTarget.disabled = loading
    this.submitTarget.textContent = loading ? 'Checking...' : 'Access Gallery'
    this.inputTarget.disabled = loading
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove('d-none')
    }
    this.inputTarget.classList.add('is-invalid')
    
    // Shake animation for visual feedback
    this.inputTarget.style.animation = 'shake 0.5s ease-in-out'
    setTimeout(() => {
      this.inputTarget.style.animation = ''
    }, 500)
    
    // Refocus input for retry
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  showSuccess() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = 'Access granted! Redirecting...'
      this.errorTarget.classList.remove('d-none')
      this.errorTarget.style.color = 'var(--success)'
    }
    this.inputTarget.classList.remove('is-invalid')
    this.submitTarget.textContent = 'Access Granted!'
    this.submitTarget.style.background = 'var(--success)'
  }

  hideError() {
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add('d-none')
    }
    this.inputTarget.classList.remove('is-invalid')
  }

  inputChanged() {
    if (this.inputTarget.value.length > 0) {
      this.hideError()
    }
  }

  // Handle Enter key
  keyPressed(event) {
    if (event.key === 'Enter') {
      event.preventDefault()
      this.submit(event)
    }
  }
}