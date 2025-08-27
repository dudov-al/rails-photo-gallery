import { Controller } from "@hotwired/stimulus"

// Enhanced loading states controller for comprehensive UX improvements
export default class extends Controller {
  static targets = ["button", "form", "content", "skeleton"]
  static values = {
    loadingText: { type: String, default: "Loading..." },
    duration: { type: Number, default: 0 },
    showSkeleton: { type: Boolean, default: false }
  }

  connect() {
    this.originalButtonTexts = new Map()
    this.setupNetworkMonitoring()
    this.setupFormInterception()
  }

  disconnect() {
    this.cleanupNetworkMonitoring()
  }

  // Button loading states
  startButtonLoading(event) {
    const button = event.currentTarget
    this.setButtonLoading(button, true)
    
    // Auto-stop loading after duration if specified
    if (this.durationValue > 0) {
      setTimeout(() => {
        this.setButtonLoading(button, false)
      }, this.durationValue)
    }
  }

  stopButtonLoading(event) {
    const button = event.currentTarget
    this.setButtonLoading(button, false)
  }

  setButtonLoading(button, loading) {
    if (loading) {
      // Store original text and set loading state
      if (!this.originalButtonTexts.has(button)) {
        this.originalButtonTexts.set(button, button.innerHTML)
      }
      
      button.disabled = true
      button.setAttribute('data-loading', 'true')
      button.setAttribute('aria-busy', 'true')
      
      // Add loading text with spinner
      button.innerHTML = `
        <span class="btn-spinner" role="status" aria-hidden="true"></span>
        ${this.loadingTextValue}
      `
    } else {
      // Restore original state
      const originalText = this.originalButtonTexts.get(button)
      if (originalText) {
        button.innerHTML = originalText
        this.originalButtonTexts.delete(button)
      }
      
      button.disabled = false
      button.removeAttribute('data-loading')
      button.setAttribute('aria-busy', 'false')
    }
  }

  // Form loading states
  startFormLoading() {
    this.formTargets.forEach(form => {
      form.classList.add('form-loading')
      
      // Disable all interactive elements
      const elements = form.querySelectorAll('input, button, select, textarea')
      elements.forEach(element => {
        element.disabled = true
      })
    })
  }

  stopFormLoading() {
    this.formTargets.forEach(form => {
      form.classList.remove('form-loading')
      
      // Re-enable interactive elements
      const elements = form.querySelectorAll('input, button, select, textarea')
      elements.forEach(element => {
        element.disabled = false
      })
    })
  }

  // Skeleton loading states
  showSkeleton() {
    if (!this.showSkeletonValue) return
    
    this.contentTargets.forEach(content => {
      content.style.display = 'none'
    })
    
    this.skeletonTargets.forEach(skeleton => {
      skeleton.style.display = 'block'
    })
  }

  hideSkeleton() {
    this.skeletonTargets.forEach(skeleton => {
      skeleton.style.display = 'none'
    })
    
    this.contentTargets.forEach(content => {
      content.style.display = 'block'
    })
  }

  // Progressive loading for content
  loadContent(event) {
    const target = event.currentTarget
    const url = target.dataset.loadUrl
    
    if (!url) return
    
    this.showSkeleton()
    
    fetch(url, {
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      this.updateContent(data)
      this.hideSkeleton()
    })
    .catch(error => {
      console.error('Content loading error:', error)
      this.showError('Failed to load content. Please try again.')
      this.hideSkeleton()
    })
  }

  updateContent(data) {
    // Override in specific controllers
    console.log('Content loaded:', data)
  }

  // Network monitoring for enhanced UX
  setupNetworkMonitoring() {
    this.networkStatus = navigator.onLine
    this.connectionBanner = this.createConnectionBanner()
    
    window.addEventListener('online', this.handleOnline.bind(this))
    window.addEventListener('offline', this.handleOffline.bind(this))
    
    // Monitor connection quality
    this.startConnectionQualityMonitoring()
  }

  cleanupNetworkMonitoring() {
    window.removeEventListener('online', this.handleOnline.bind(this))
    window.removeEventListener('offline', this.handleOffline.bind(this))
    
    if (this.connectionMonitorInterval) {
      clearInterval(this.connectionMonitorInterval)
    }
  }

  handleOnline() {
    this.networkStatus = true
    this.hideConnectionBanner()
    this.showToast('Connection restored', 'success')
  }

  handleOffline() {
    this.networkStatus = false
    this.showConnectionBanner('offline')
  }

  createConnectionBanner() {
    const banner = document.createElement('div')
    banner.className = 'network-error-banner'
    banner.setAttribute('role', 'alert')
    banner.setAttribute('aria-live', 'assertive')
    
    banner.innerHTML = `
      <div class="error-content">
        <svg class="error-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor">
          <path d="M12 2L2 7v10c0 5.55 3.84 10 9 10s9-4.45 9-10V7l-10-5z"/>
          <path d="M8 12l2 2 4-4"/>
        </svg>
        <div class="error-message">
          <span class="error-text">Connection lost. Some features may not work properly.</span>
        </div>
        <button class="retry-button" data-action="click->loading#retryConnection">
          Retry
        </button>
        <button class="dismiss-button" data-action="click->loading#dismissBanner">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>
      </div>
    `
    
    document.body.appendChild(banner)
    return banner
  }

  showConnectionBanner(type) {
    if (!this.connectionBanner) return
    
    this.connectionBanner.className = `network-error-banner ${type} show`
    
    const errorText = this.connectionBanner.querySelector('.error-text')
    if (type === 'offline') {
      errorText.textContent = 'No internet connection. Please check your network.'
    } else if (type === 'slow') {
      errorText.textContent = 'Slow connection detected. Some features may be delayed.'
    }
  }

  hideConnectionBanner() {
    if (this.connectionBanner) {
      this.connectionBanner.classList.remove('show')
    }
  }

  dismissBanner() {
    this.hideConnectionBanner()
  }

  retryConnection() {
    this.hideConnectionBanner()
    
    // Test connection
    fetch('/health-check', { method: 'HEAD', cache: 'no-cache' })
      .then(() => {
        this.showToast('Connection restored successfully', 'success')
      })
      .catch(() => {
        this.showToast('Connection test failed. Please check your network.', 'error')
        setTimeout(() => this.showConnectionBanner('offline'), 2000)
      })
  }

  startConnectionQualityMonitoring() {
    if (!navigator.connection) return
    
    const connection = navigator.connection
    this.connectionMonitorInterval = setInterval(() => {
      if (connection.effectiveType === '2g' || connection.downlink < 0.5) {
        if (this.networkStatus && !this.connectionBanner.classList.contains('show')) {
          this.showConnectionBanner('slow')
        }
      }
    }, 10000) // Check every 10 seconds
  }

  // Form submission interception for better UX
  setupFormInterception() {
    this.formTargets.forEach(form => {
      form.addEventListener('submit', this.handleFormSubmit.bind(this))
    })
  }

  handleFormSubmit(event) {
    if (!this.networkStatus) {
      event.preventDefault()
      this.showError('No internet connection. Please check your network and try again.')
      return false
    }
    
    // Start loading state
    this.startFormLoading()
    
    // Set timeout for long-running requests
    const timeout = setTimeout(() => {
      this.showToast('This is taking longer than expected...', 'info')
    }, 5000)
    
    // Clean up on form response
    const cleanup = () => {
      clearTimeout(timeout)
      this.stopFormLoading()
    }
    
    // Listen for Turbo events
    document.addEventListener('turbo:submit-end', cleanup, { once: true })
    document.addEventListener('turbo:frame-load', cleanup, { once: true })
    
    return true
  }

  // Utility methods
  showError(message) {
    this.showToast(message, 'error')
  }

  showToast(message, type = 'info') {
    const toast = this.createToast(message, type)
    document.body.appendChild(toast)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (toast.parentNode) {
        toast.remove()
      }
    }, 5000)
  }

  createToast(message, type) {
    const toast = document.createElement('div')
    toast.className = `toast toast-${type}`
    toast.setAttribute('role', 'alert')
    toast.setAttribute('aria-live', 'assertive')
    
    const icon = this.getToastIcon(type)
    
    toast.innerHTML = `
      <div class="toast-header">
        ${icon}
        <strong class="toast-title">${this.getToastTitle(type)}</strong>
        <button type="button" class="toast-close" data-action="click->loading#dismissToast">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>
      </div>
      <div class="toast-body">${message}</div>
    `
    
    // Position toast
    const container = this.getToastContainer()
    container.appendChild(toast)
    
    return toast
  }

  getToastContainer() {
    let container = document.querySelector('.toast-container')
    if (!container) {
      container = document.createElement('div')
      container.className = 'toast-container'
      document.body.appendChild(container)
    }
    return container
  }

  dismissToast(event) {
    const toast = event.currentTarget.closest('.toast')
    if (toast) {
      toast.remove()
    }
  }

  getToastIcon(type) {
    const icons = {
      success: '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22,4 12,14.01 9,11.01"></polyline></svg>',
      error: '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"></circle><line x1="15" y1="9" x2="9" y2="15"></line><line x1="9" y1="9" x2="15" y2="15"></line></svg>',
      warning: '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg>',
      info: '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"></circle><path d="m9 12 2 2 4-4"></path></svg>'
    }
    return icons[type] || icons.info
  }

  getToastTitle(type) {
    const titles = {
      success: 'Success',
      error: 'Error',
      warning: 'Warning',
      info: 'Information'
    }
    return titles[type] || 'Notification'
  }
}