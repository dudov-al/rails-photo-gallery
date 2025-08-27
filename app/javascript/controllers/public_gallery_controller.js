import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="public-gallery"
export default class extends Controller {
  static targets = ["grid", "item", "lightbox", "lightboxImage", "lightboxCounter", "prevBtn", "nextBtn", "closeBtn"]
  static values = { 
    images: Array, 
    currentIndex: Number,
    downloadAllUrl: String
  }

  connect() {
    this.currentIndexValue = 0
    this.setupImageLoading()
    this.setupKeyboardListeners()
    this.setupTouchListeners()
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeyboard)
    this.removeEventListener('touchstart', this.handleTouchStart)
    this.removeEventListener('touchend', this.handleTouchEnd)
  }

  setupImageLoading() {
    // Implement intersection observer for lazy loading
    if ('IntersectionObserver' in window) {
      const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const img = entry.target
            this.loadImage(img)
            observer.unobserve(img)
          }
        })
      }, {
        rootMargin: '50px 0px'
      })

      this.itemTargets.forEach(item => {
        const img = item.querySelector('img')
        if (img && !img.src) {
          imageObserver.observe(img)
        }
      })
    } else {
      // Fallback for browsers without IntersectionObserver
      this.itemTargets.forEach(item => {
        const img = item.querySelector('img')
        if (img && !img.src) {
          this.loadImage(img)
        }
      })
    }
  }

  loadImage(img) {
    const thumbnail = img.dataset.thumbnail
    const placeholder = img.previousElementSibling

    if (thumbnail) {
      const tempImg = new Image()
      tempImg.onload = () => {
        img.src = thumbnail
        img.classList.add('loaded')
        if (placeholder) {
          placeholder.style.opacity = '0'
          setTimeout(() => placeholder.remove(), 300)
        }
      }
      tempImg.onerror = () => {
        console.warn('Failed to load image:', thumbnail)
        if (placeholder) {
          placeholder.innerHTML = '<i class="fas fa-image" style="font-size: 2rem; color: #ccc;"></i>'
        }
      }
      tempImg.src = thumbnail
    }
  }

  openLightbox(event) {
    event.preventDefault()
    const imageIndex = parseInt(event.currentTarget.dataset.imageIndex)
    this.currentIndexValue = imageIndex
    this.showLightbox()
  }

  showLightbox() {
    this.updateLightboxImage()
    this.lightboxTarget.classList.add('active')
    document.body.style.overflow = 'hidden'
  }

  closeLightbox() {
    this.lightboxTarget.classList.remove('active')
    document.body.style.overflow = 'auto'
  }

  nextImage() {
    if (this.currentIndexValue < this.imagesValue.length - 1) {
      this.currentIndexValue++
      this.updateLightboxImage()
    }
  }

  prevImage() {
    if (this.currentIndexValue > 0) {
      this.currentIndexValue--
      this.updateLightboxImage()
    }
  }

  updateLightboxImage() {
    const currentImage = this.imagesValue[this.currentIndexValue]
    if (!currentImage) return

    // Update image
    this.lightboxImageTarget.src = currentImage.web_url
    this.lightboxImageTarget.alt = currentImage.alt_text

    // Update counter
    this.lightboxCounterTarget.textContent = 
      `${this.currentIndexValue + 1} / ${this.imagesValue.length}`

    // Update navigation buttons
    this.prevBtnTarget.style.display = 
      this.currentIndexValue > 0 ? 'block' : 'none'
    this.nextBtnTarget.style.display = 
      this.currentIndexValue < this.imagesValue.length - 1 ? 'block' : 'none'
  }

  downloadImage(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const imageIndex = parseInt(event.currentTarget.dataset.imageIndex)
    const image = this.imagesValue[imageIndex]
    
    if (image) {
      this.performDownload(image.download_url, image.filename)
    }
  }

  downloadCurrentImage() {
    const currentImage = this.imagesValue[this.currentIndexValue]
    if (currentImage) {
      this.performDownload(currentImage.download_url, currentImage.filename)
    }
  }

  downloadAll() {
    if (this.downloadAllUrlValue) {
      this.performDownload(this.downloadAllUrlValue, 'gallery-photos.zip')
    }
  }

  performDownload(url, filename) {
    // Show loading state
    const downloadBtn = event.target.closest('button, a')
    const originalText = downloadBtn.textContent
    downloadBtn.disabled = true
    downloadBtn.textContent = 'Downloading...'

    // Create temporary link for download
    const link = document.createElement('a')
    link.href = url
    link.download = filename
    link.style.display = 'none'
    
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)

    // Reset button state
    setTimeout(() => {
      downloadBtn.disabled = false
      downloadBtn.textContent = originalText
    }, 1500)
  }

  setupKeyboardListeners() {
    this.handleKeyboard = this.handleKeyboard.bind(this)
    document.addEventListener('keydown', this.handleKeyboard)
  }

  handleKeyboard(event) {
    if (!this.lightboxTarget.classList.contains('active')) return

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
    this.handleTouchStart = this.handleTouchStart.bind(this)
    this.handleTouchEnd = this.handleTouchEnd.bind(this)
    
    if (this.lightboxTarget) {
      this.lightboxTarget.addEventListener('touchstart', this.handleTouchStart, { passive: true })
      this.lightboxTarget.addEventListener('touchend', this.handleTouchEnd, { passive: true })
    }
  }

  handleTouchStart(event) {
    this.startX = event.touches[0].clientX
    this.startY = event.touches[0].clientY
  }

  handleTouchEnd(event) {
    if (!this.startX || !this.startY) return

    const endX = event.changedTouches[0].clientX
    const endY = event.changedTouches[0].clientY
    const diffX = this.startX - endX
    const diffY = this.startY - endY

    // Check if it's a horizontal swipe (more horizontal than vertical)
    if (Math.abs(diffX) > Math.abs(diffY) && Math.abs(diffX) > 50) {
      if (diffX > 0) {
        // Swipe left - next image
        this.nextImage()
      } else {
        // Swipe right - previous image
        this.prevImage()
      }
    }

    this.startX = null
    this.startY = null
  }

  // Handle backdrop click to close lightbox
  backdropClick(event) {
    if (event.target === event.currentTarget) {
      this.closeLightbox()
    }
  }
}