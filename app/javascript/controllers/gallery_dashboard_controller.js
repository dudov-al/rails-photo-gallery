import { Controller } from "@hotwired/stimulus"

// Enhanced gallery dashboard with comprehensive loading states and UX improvements
export default class extends Controller {
  static targets = [
    "galleriesGrid", "searchForm", "searchInput", "filterSelect", "sortSelect",
    "loadingState", "emptyState", "statsCards", "paginationContainer"
  ]
  
  static values = {
    currentPage: { type: Number, default: 1 },
    totalPages: { type: Number, default: 1 },
    searchQuery: { type: String, default: "" },
    currentFilter: { type: String, default: "" },
    currentSort: { type: String, default: "" },
    autoRefresh: { type: Boolean, default: false },
    refreshInterval: { type: Number, default: 30000 }
  }

  connect() {
    this.setupProgressiveEnhancement()
    this.setupKeyboardNavigation()
    this.setupAutoRefresh()
    this.loadGalleries()
    
    // Add connection status monitoring
    this.application.getControllerForElementAndIdentifier(document.body, "loading")
  }

  disconnect() {
    this.cleanupAutoRefresh()
  }

  // Progressive loading with skeleton screens
  loadGalleries(showLoading = true) {
    if (showLoading) {
      this.showLoadingState()
    }
    
    const params = new URLSearchParams({
      page: this.currentPageValue,
      search: this.searchQueryValue,
      filter: this.currentFilterValue,
      sort: this.currentSortValue,
      format: 'json'
    })
    
    const url = `/galleries?${params.toString()}`
    
    return fetch(url, {
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }
      return response.json()
    })
    .then(data => {
      this.updateGalleries(data.galleries)
      this.updateStats(data.stats)
      this.updatePagination(data.pagination)
      this.hideLoadingState()
    })
    .catch(error => {
      console.error('Failed to load galleries:', error)
      this.showError('Failed to load galleries. Please try refreshing the page.')
      this.hideLoadingState()
    })
  }

  // Search functionality with debouncing
  handleSearch(event) {
    clearTimeout(this.searchTimeout)
    
    const query = event.target.value.trim()
    this.searchQueryValue = query
    
    // Show immediate visual feedback
    this.markSearchAsActive()
    
    // Debounce the actual search
    this.searchTimeout = setTimeout(() => {
      this.currentPageValue = 1
      this.loadGalleries()
    }, 300)
  }

  // Filter and sort handlers
  handleFilter(event) {
    this.currentFilterValue = event.target.value
    this.currentPageValue = 1
    this.loadGalleries()
  }

  handleSort(event) {
    this.currentSortValue = event.target.value
    this.currentPageValue = 1
    this.loadGalleries()
  }

  // Clear all filters
  clearFilters() {
    this.searchQueryValue = ""
    this.currentFilterValue = ""
    this.currentSortValue = ""
    this.currentPageValue = 1
    
    // Reset form elements
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }
    if (this.hasFilterSelectTarget) {
      this.filterSelectTarget.selectedIndex = 0
    }
    if (this.hasSortSelectTarget) {
      this.sortSelectTarget.selectedIndex = 0
    }
    
    this.loadGalleries()
  }

  // Pagination
  loadPage(event) {
    event.preventDefault()
    const page = parseInt(event.currentTarget.dataset.page)
    
    if (page && page !== this.currentPageValue) {
      this.currentPageValue = page
      this.loadGalleries()
      
      // Smooth scroll to top
      this.galleriesGridTarget.scrollIntoView({ behavior: 'smooth' })
    }
  }

  // Gallery actions
  async deleteGallery(event) {
    event.preventDefault()
    
    const galleryId = event.currentTarget.dataset.galleryId
    const galleryTitle = event.currentTarget.dataset.galleryTitle
    
    if (!confirm(`Are you sure you want to delete "${galleryTitle}"? This action cannot be undone.`)) {
      return
    }
    
    try {
      this.showLoadingButton(event.currentTarget)
      
      const response = await fetch(`/galleries/${galleryId}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        this.showToast('Gallery deleted successfully', 'success')
        this.removeGalleryFromGrid(galleryId)
        this.refreshStats()
      } else {
        throw new Error('Failed to delete gallery')
      }
    } catch (error) {
      console.error('Delete error:', error)
      this.showError('Failed to delete gallery. Please try again.')
    } finally {
      this.hideLoadingButton(event.currentTarget)
    }
  }

  async duplicateGallery(event) {
    event.preventDefault()
    
    const galleryId = event.currentTarget.dataset.galleryId
    const galleryTitle = event.currentTarget.dataset.galleryTitle
    
    try {
      this.showLoadingButton(event.currentTarget)
      
      const response = await fetch(`/galleries/${galleryId}/duplicate`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })
      
      const data = await response.json()
      
      if (response.ok) {
        this.showToast(`"${galleryTitle}" duplicated successfully`, 'success')
        this.loadGalleries()
      } else {
        throw new Error(data.error || 'Failed to duplicate gallery')
      }
    } catch (error) {
      console.error('Duplicate error:', error)
      this.showError('Failed to duplicate gallery. Please try again.')
    } finally {
      this.hideLoadingButton(event.currentTarget)
    }
  }

  // Bulk actions
  toggleGallerySelection(event) {
    const checkbox = event.target
    const galleryCard = checkbox.closest('.gallery-card')
    
    if (checkbox.checked) {
      galleryCard.classList.add('selected')
    } else {
      galleryCard.classList.remove('selected')
    }
    
    this.updateBulkActionsVisibility()
  }

  selectAllGalleries(event) {
    const selectAll = event.target.checked
    const checkboxes = this.element.querySelectorAll('.gallery-checkbox')
    
    checkboxes.forEach(checkbox => {
      checkbox.checked = selectAll
      this.toggleGallerySelection({ target: checkbox })
    })
  }

  // Auto-refresh functionality
  setupAutoRefresh() {
    if (this.autoRefreshValue) {
      this.refreshTimer = setInterval(() => {
        this.loadGalleries(false) // Silent refresh
      }, this.refreshIntervalValue)
    }
  }

  cleanupAutoRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  // UI State Management
  showLoadingState() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.style.display = 'block'
    }
    
    if (this.hasGalleriesGridTarget) {
      this.galleriesGridTarget.style.display = 'none'
    }
    
    this.showSkeletonCards()
  }

  hideLoadingState() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.style.display = 'none'
    }
    
    if (this.hasGalleriesGridTarget) {
      this.galleriesGridTarget.style.display = 'block'
    }
    
    this.hideSkeletonCards()
  }

  showSkeletonCards() {
    const skeletonHTML = this.generateSkeletonCards(6) // Show 6 skeleton cards
    const tempContainer = document.createElement('div')
    tempContainer.innerHTML = skeletonHTML
    tempContainer.className = 'gallery-skeleton row'
    
    this.galleriesGridTarget.appendChild(tempContainer)
  }

  hideSkeletonCards() {
    const skeleton = this.element.querySelector('.gallery-skeleton')
    if (skeleton) {
      skeleton.remove()
    }
  }

  generateSkeletonCards(count) {
    let html = ''
    for (let i = 0; i < count; i++) {
      html += `
        <div class="col-xl-3 col-lg-4 col-md-6 mb-4">
          <div class="card h-100">
            <div class="skeleton-item skeleton-image"></div>
            <div class="card-body">
              <div class="skeleton-item skeleton-title"></div>
              <div class="skeleton-item skeleton-text"></div>
              <div class="skeleton-item skeleton-text" style="width: 60%;"></div>
            </div>
            <div class="card-footer">
              <div class="skeleton-item skeleton-button"></div>
            </div>
          </div>
        </div>
      `
    }
    return html
  }

  // Update methods
  updateGalleries(galleries) {
    if (!galleries || galleries.length === 0) {
      this.showEmptyState()
      return
    }
    
    this.hideEmptyState()
    
    const galleryHTML = galleries.map(gallery => this.generateGalleryCard(gallery)).join('')
    this.galleriesGridTarget.innerHTML = galleryHTML
    
    // Animate in new cards
    this.animateGalleryCards()
  }

  updateStats(stats) {
    if (!this.hasStatsCardsTarget || !stats) return
    
    const statElements = {
      'total_galleries': this.element.querySelector('[data-stat="total_galleries"]'),
      'published_galleries': this.element.querySelector('[data-stat="published_galleries"]'),
      'total_images': this.element.querySelector('[data-stat="total_images"]'),
      'total_views': this.element.querySelector('[data-stat="total_views"]'),
      'featured_galleries': this.element.querySelector('[data-stat="featured_galleries"]'),
      'password_protected_galleries': this.element.querySelector('[data-stat="password_protected_galleries"]')
    }
    
    Object.entries(stats).forEach(([key, value]) => {
      const element = statElements[key]
      if (element) {
        this.animateNumber(element, value)
      }
    })
  }

  updatePagination(pagination) {
    if (!this.hasPaginationContainerTarget || !pagination) return
    
    this.totalPagesValue = pagination.pages
    
    if (pagination.pages <= 1) {
      this.paginationContainerTarget.style.display = 'none'
      return
    }
    
    this.paginationContainerTarget.style.display = 'block'
    this.paginationContainerTarget.innerHTML = this.generatePaginationHTML(pagination)
  }

  // Helper methods
  generateGalleryCard(gallery) {
    const statusBadges = this.generateStatusBadges(gallery)
    const thumbnailUrl = gallery.thumbnail_url || '/assets/placeholder-gallery.svg'
    
    return `
      <div class="col-xl-3 col-lg-4 col-md-6 mb-4" data-gallery-id="${gallery.id}">
        <div class="card h-100 gallery-card">
          <div class="card-img-top position-relative" style="height: 200px; overflow: hidden; background: #f8f9fa;">
            <img src="${thumbnailUrl}" 
                 alt="${gallery.title}" 
                 class="w-100 h-100" 
                 style="object-fit: cover;"
                 loading="lazy">
            ${statusBadges}
            <div class="position-absolute bottom-0 end-0 p-2">
              <span class="badge bg-dark bg-opacity-75">
                <i class="fas fa-images me-1"></i>${gallery.images_count || 0}
              </span>
            </div>
          </div>
          
          <div class="card-body">
            <h5 class="card-title">${this.truncate(gallery.title, 50)}</h5>
            ${gallery.description ? `<p class="card-text text-muted small">${this.truncate(gallery.description, 80)}</p>` : ''}
            
            <div class="row g-0 mb-3 text-center">
              <div class="col">
                <small class="text-muted">
                  <i class="fas fa-eye me-1"></i>${gallery.views_count || 0} views
                </small>
              </div>
              <div class="col">
                <small class="text-muted">
                  ${this.timeAgo(gallery.created_at)}
                </small>
              </div>
            </div>
            
            ${gallery.viewable ? this.generatePublicLink(gallery) : ''}
          </div>
          
          <div class="card-footer bg-transparent">
            ${this.generateGalleryActions(gallery)}
          </div>
        </div>
      </div>
    `
  }

  generateStatusBadges(gallery) {
    let badges = ''
    
    if (!gallery.published) badges += '<span class="badge bg-secondary">Draft</span> '
    if (gallery.featured) badges += '<span class="badge bg-warning">Featured</span> '
    if (gallery.password_protected) badges += '<span class="badge bg-info">Protected</span> '
    if (gallery.expired) badges += '<span class="badge bg-danger">Expired</span> '
    
    return badges ? `<div class="position-absolute top-0 start-0 p-2">${badges}</div>` : ''
  }

  generatePublicLink(gallery) {
    return `
      <div class="mb-3">
        <a href="/galleries/${gallery.slug}" 
           class="btn btn-outline-success btn-sm" 
           target="_blank"
           rel="noopener noreferrer">
          <i class="fas fa-external-link-alt me-1"></i>View Public Gallery
        </a>
      </div>
    `
  }

  generateGalleryActions(gallery) {
    return `
      <div class="d-flex gap-1 flex-wrap">
        <a href="/galleries/${gallery.id}/edit" class="btn btn-primary btn-sm flex-fill">Edit</a>
        <a href="/galleries/${gallery.id}/images" class="btn btn-outline-primary btn-sm flex-fill">Images</a>
        
        <div class="dropdown">
          <button class="btn btn-outline-secondary btn-sm dropdown-toggle" 
                  type="button" 
                  data-bs-toggle="dropdown"
                  aria-expanded="false">
            <i class="fas fa-ellipsis-v"></i>
          </button>
          <ul class="dropdown-menu">
            <li>
              <button class="dropdown-item" 
                      data-action="click->gallery-dashboard#duplicateGallery"
                      data-gallery-id="${gallery.id}"
                      data-gallery-title="${gallery.title}">
                <i class="fas fa-copy me-2"></i>Duplicate
              </button>
            </li>
            <li><hr class="dropdown-divider"></li>
            <li>
              <button class="dropdown-item text-danger" 
                      data-action="click->gallery-dashboard#deleteGallery"
                      data-gallery-id="${gallery.id}"
                      data-gallery-title="${gallery.title}">
                <i class="fas fa-trash me-2"></i>Delete
              </button>
            </li>
          </ul>
        </div>
      </div>
    `
  }

  // Progressive enhancement and accessibility
  setupProgressiveEnhancement() {
    // Enable real-time search if JavaScript is available
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.setAttribute('autocomplete', 'off')
      this.searchInputTarget.setAttribute('spellcheck', 'false')
    }
    
    // Add keyboard shortcuts
    document.addEventListener('keydown', (event) => {
      if (event.ctrlKey || event.metaKey) {
        switch (event.key) {
          case '/':
            event.preventDefault()
            this.focusSearch()
            break
          case 'n':
            if (event.shiftKey) {
              event.preventDefault()
              window.location.href = '/galleries/new'
            }
            break
        }
      }
    })
  }

  setupKeyboardNavigation() {
    // Add ARIA labels and keyboard navigation
    const galleryCards = this.element.querySelectorAll('.gallery-card')
    galleryCards.forEach((card, index) => {
      card.setAttribute('role', 'article')
      card.setAttribute('aria-label', `Gallery ${index + 1}`)
    })
  }

  focusSearch() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.focus()
      this.searchInputTarget.select()
    }
  }

  // Utility methods
  showEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.style.display = 'block'
    }
    if (this.hasGalleriesGridTarget) {
      this.galleriesGridTarget.style.display = 'none'
    }
  }

  hideEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.style.display = 'none'
    }
    if (this.hasGalleriesGridTarget) {
      this.galleriesGridTarget.style.display = 'block'
    }
  }

  markSearchAsActive() {
    if (this.hasSearchFormTarget) {
      this.searchFormTarget.classList.add('searching')
    }
  }

  showLoadingButton(button) {
    const original = button.innerHTML
    button.setAttribute('data-original-text', original)
    button.disabled = true
    button.innerHTML = '<i class="fas fa-spinner fa-spin me-1"></i>Processing...'
  }

  hideLoadingButton(button) {
    const originalText = button.getAttribute('data-original-text')
    if (originalText) {
      button.innerHTML = originalText
      button.removeAttribute('data-original-text')
    }
    button.disabled = false
  }

  removeGalleryFromGrid(galleryId) {
    const galleryElement = this.element.querySelector(`[data-gallery-id="${galleryId}"]`)
    if (galleryElement) {
      galleryElement.style.transform = 'scale(0.8)'
      galleryElement.style.opacity = '0'
      
      setTimeout(() => {
        galleryElement.remove()
        
        // Check if grid is now empty
        const remainingGalleries = this.galleriesGridTarget.querySelectorAll('[data-gallery-id]')
        if (remainingGalleries.length === 0) {
          this.showEmptyState()
        }
      }, 300)
    }
  }

  animateGalleryCards() {
    const cards = this.galleriesGridTarget.querySelectorAll('.gallery-card')
    cards.forEach((card, index) => {
      card.style.opacity = '0'
      card.style.transform = 'translateY(20px)'
      
      setTimeout(() => {
        card.style.transition = 'opacity 0.3s ease, transform 0.3s ease'
        card.style.opacity = '1'
        card.style.transform = 'translateY(0)'
      }, index * 50)
    })
  }

  animateNumber(element, targetValue) {
    const currentValue = parseInt(element.textContent) || 0
    const increment = Math.ceil((targetValue - currentValue) / 20)
    
    const animate = () => {
      const current = parseInt(element.textContent) || 0
      if (current < targetValue) {
        element.textContent = Math.min(current + increment, targetValue)
        requestAnimationFrame(animate)
      } else {
        element.textContent = targetValue
      }
    }
    
    animate()
  }

  truncate(str, length) {
    return str.length > length ? str.substring(0, length) + '...' : str
  }

  timeAgo(dateString) {
    const date = new Date(dateString)
    const now = new Date()
    const seconds = Math.floor((now - date) / 1000)
    
    const intervals = {
      year: 31536000,
      month: 2592000,
      week: 604800,
      day: 86400,
      hour: 3600,
      minute: 60
    }
    
    for (const [unit, secondsInUnit] of Object.entries(intervals)) {
      const interval = Math.floor(seconds / secondsInUnit)
      if (interval >= 1) {
        return `${interval} ${unit}${interval > 1 ? 's' : ''} ago`
      }
    }
    
    return 'Just now'
  }

  refreshStats() {
    // Reload just the stats without reloading entire page
    fetch('/galleries/stats', {
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      this.updateStats(data.stats)
    })
    .catch(error => {
      console.error('Failed to refresh stats:', error)
    })
  }

  // Toast notifications (delegated to loading controller)
  showToast(message, type) {
    const loadingController = this.application.getControllerForElementAndIdentifier(document.body, "loading")
    if (loadingController) {
      loadingController.showToast(message, type)
    }
  }

  showError(message) {
    this.showToast(message, 'error')
  }
}