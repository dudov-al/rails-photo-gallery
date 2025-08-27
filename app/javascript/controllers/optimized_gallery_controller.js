import { Controller } from "@hotwired/stimulus"

// High-performance optimized gallery controller
export default class extends Controller {
  static targets = ["grid", "item", "lightbox", "lightboxImage", "lightboxCounter", "prevBtn", "nextBtn", "closeBtn"]
  static values = { 
    images: Array, 
    currentIndex: Number,
    downloadAllUrl: String
  }

  connect() {
    this.currentIndexValue = 0
    this.preloadedImages = new Map()
    this.intersectionObserver = null
    this.touchStartX = null
    this.touchStartY = null
    
    this.setupIntersectionObserver()
    this.setupKeyboardListeners()
    this.setupTouchListeners()
    this.setupPreloading()
  }

  disconnect() {
    this.cleanupObservers()
    this.cleanupEventListeners()
  }

  // Optimized lazy loading with Intersection Observer
  setupIntersectionObserver() {
    if (\!('IntersectionObserver' in window)) {
      this.fallbackImageLoading()
      return
    }

    this.intersectionObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          this.loadImage(entry.target)
          this.intersectionObserver.unobserve(entry.target)
        }
      })
    }, {
      rootMargin: '50px 0px',
      threshold: 0.1
    })

    this.itemTargets.forEach(item => {
      const img = item.querySelector('img[data-thumbnail]')
      if (img && \!img.src) {
        this.intersectionObserver.observe(img)
      }
    })
  }

  // Optimized image loading with error handling and performance monitoring
  loadImage(img) {
    const thumbnail = img.dataset.thumbnail
    const placeholder = img.previousElementSibling
    
    if (\!thumbnail || this.preloadedImages.has(thumbnail)) return

    const startTime = performance.now()
    const tempImg = new Image()
    
    tempImg.onload = () => {
      const loadTime = performance.now() - startTime
      
      img.src = thumbnail
      img.classList.add('loaded')
      this.preloadedImages.set(thumbnail, true)
      
      if (placeholder) {
        placeholder.style.opacity = '0'
        setTimeout(() => placeholder?.remove(), 300)
      }
      
      // Log slow loading images for optimization
      if (loadTime > 1000) {
        console.warn('Slow image load: ' + thumbnail + ' took ' + loadTime + 'ms')
      }
    }
    
    tempImg.onerror = () => {
      console.error('Failed to load image:', thumbnail)
      this.handleImageError(img, placeholder)
    }
    
    // Set loading priority
    tempImg.loading = 'lazy'
    tempImg.decoding = 'async'
    tempImg.src = thumbnail
  }

  handleImageError(img, placeholder) {
    if (placeholder) {
      placeholder.innerHTML = '<div style="display: flex; align-items: center; justify-content: center; height: 100%; color: #ccc;"><svg width="48" height="48" viewBox="0 0 24 24" fill="currentColor"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg></div>'
    }
  }

  // Intelligent preloading for better UX
  setupPreloading() {
    // Preload the first few web-size images for lightbox
    const priorityImages = this.imagesValue.slice(0, 3)
    
    if (window.requestIdleCallback) {
      requestIdleCallback(() => {
        priorityImages.forEach(image => {
          const webImg = new Image()
          webImg.src = image.web_url
          webImg.loading = 'eager'
          this.preloadedImages.set(image.web_url, true)
        })
      })
    }
  }

  // Optimized lightbox with smooth animations
  openLightbox(event) {
    event.preventDefault()
    const imageIndex = parseInt(event.currentTarget.dataset.imageIndex)
    this.currentIndexValue = imageIndex
    
    // Preload adjacent images for smooth navigation
    this.preloadAdjacentImages(imageIndex)
    
    this.showLightbox()
  }

  preloadAdjacentImages(currentIndex) {
    const adjacentIndexes = [currentIndex - 1, currentIndex + 1].filter(
      i => i >= 0 && i < this.imagesValue.length
    )
    
    adjacentIndexes.forEach(index => {
      const image = this.imagesValue[index]
      if (image && \!this.preloadedImages.has(image.web_url)) {
        const webImg = new Image()
        webImg.src = image.web_url
        this.preloadedImages.set(image.web_url, true)
      }
    })
  }

  showLightbox() {
    this.updateLightboxImage()
    this.lightboxTarget.classList.add('active')
    document.body.style.overflow = 'hidden'
    
    // Focus management for accessibility
    this.lightboxTarget.focus()
  }

  closeLightbox() {
    this.lightboxTarget.classList.remove('active')
    document.body.style.overflow = 'auto'
  }

  nextImage() {
    if (this.currentIndexValue < this.imagesValue.length - 1) {
      this.currentIndexValue++
      this.updateLightboxImage()
      this.preloadAdjacentImages(this.currentIndexValue)
    }
  }

  prevImage() {
    if (this.currentIndexValue > 0) {
      this.currentIndexValue--
      this.updateLightboxImage()
      this.preloadAdjacentImages(this.currentIndexValue)
    }
  }

  // Other methods continue...
  updateLightboxImage() {
    const currentImage = this.imagesValue[this.currentIndexValue]
    if (\!currentImage) return

    const lightboxImg = this.lightboxImageTarget
    lightboxImg.style.opacity = '0.5'
    
    if (this.preloadedImages.has(currentImage.web_url)) {
      lightboxImg.src = currentImage.web_url
      lightboxImg.style.opacity = '1'
    } else {
      const webImg = new Image()
      webImg.onload = () => {
        lightboxImg.src = currentImage.web_url
        lightboxImg.style.opacity = '1'
        this.preloadedImages.set(currentImage.web_url, true)
      }
      webImg.src = currentImage.web_url
    }
    
    lightboxImg.alt = currentImage.alt_text

    this.lightboxCounterTarget.textContent = 
      (this.currentIndexValue + 1) + ' / ' + this.imagesValue.length

    this.prevBtnTarget.style.display = 
      this.currentIndexValue > 0 ? 'block' : 'none'
    this.nextBtnTarget.style.display = 
      this.currentIndexValue < this.imagesValue.length - 1 ? 'block' : 'none'
  }

  setupKeyboardListeners() {
    this.boundKeyboardHandler = this.handleKeyboard.bind(this)
    document.addEventListener('keydown', this.boundKeyboardHandler)
  }

  handleKeyboard(event) {
    if (\!this.lightboxTarget.classList.contains('active')) return

    switch(event.key) {
      case 'Escape':
        event.preventDefault()
        this.closeLightbox()
        break
      case 'ArrowLeft':
        event.preventDefault()
        this.prevImage()
        break
      case 'ArrowRight':
        event.preventDefault()
        this.nextImage()
        break
      case ' ':
        event.preventDefault()
        this.nextImage()
        break
    }
  }

  setupTouchListeners() {
    this.boundTouchStart = this.handleTouchStart.bind(this)
    this.boundTouchEnd = this.handleTouchEnd.bind(this)
    
    if (this.lightboxTarget) {
      this.lightboxTarget.addEventListener('touchstart', this.boundTouchStart, { passive: true })
      this.lightboxTarget.addEventListener('touchend', this.boundTouchEnd, { passive: true })
    }
  }

  handleTouchStart(event) {
    this.touchStartX = event.touches[0].clientX
    this.touchStartY = event.touches[0].clientY
  }

  handleTouchEnd(event) {
    if (\!this.touchStartX || \!this.touchStartY) return

    const endX = event.changedTouches[0].clientX
    const endY = event.changedTouches[0].clientY
    const diffX = this.touchStartX - endX
    const diffY = this.touchStartY - endY

    if (Math.abs(diffX) > Math.abs(diffY) && Math.abs(diffX) > 50) {
      if (diffX > 0) {
        this.nextImage()
      } else {
        this.prevImage()
      }
    }

    this.touchStartX = null
    this.touchStartY = null
  }

  backdropClick(event) {
    if (event.target === event.currentTarget) {
      this.closeLightbox()
    }
  }

  cleanupObservers() {
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect()
    }
  }

  cleanupEventListeners() {
    if (this.boundKeyboardHandler) {
      document.removeEventListener('keydown', this.boundKeyboardHandler)
    }
    if (this.boundTouchStart) {
      this.lightboxTarget?.removeEventListener('touchstart', this.boundTouchStart)
    }
    if (this.boundTouchEnd) {
      this.lightboxTarget?.removeEventListener('touchend', this.boundTouchEnd)
    }
  }

  fallbackImageLoading() {
    this.itemTargets.forEach(item => {
      const img = item.querySelector('img[data-thumbnail]')
      if (img && \!img.src) {
        this.loadImage(img)
      }
    })
  }
}
EOF < /dev/null