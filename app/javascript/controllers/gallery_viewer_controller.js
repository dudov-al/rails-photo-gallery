import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="gallery-viewer"
export default class extends Controller {
  static targets = ["modal", "modalImage", "modalTitle", "prevButton", "nextButton"]
  static values = { images: Array, currentIndex: Number }

  connect() {
    this.currentIndexValue = 0
  }

  showImage(event) {
    const imageIndex = parseInt(event.currentTarget.dataset.imageIndex)
    this.currentIndexValue = imageIndex
    this.updateModal()
    this.showModal()
  }

  previousImage() {
    if (this.currentIndexValue > 0) {
      this.currentIndexValue--
      this.updateModal()
    }
  }

  nextImage() {
    if (this.currentIndexValue < this.imagesValue.length - 1) {
      this.currentIndexValue++
      this.updateModal()
    }
  }

  updateModal() {
    const currentImage = this.imagesValue[this.currentIndexValue]
    
    if (!currentImage) return

    this.modalImageTarget.src = currentImage.web_url
    this.modalImageTarget.alt = currentImage.filename
    this.modalTitleTarget.textContent = currentImage.filename

    // Update navigation buttons
    this.prevButtonTarget.disabled = this.currentIndexValue === 0
    this.nextButtonTarget.disabled = this.currentIndexValue === this.imagesValue.length - 1

    // Add download link
    this.updateDownloadLink(currentImage)
  }

  updateDownloadLink(image) {
    const downloadButton = this.modalTarget.querySelector('.download-btn')
    if (downloadButton) {
      downloadButton.href = image.download_url
      downloadButton.download = image.filename
    }
  }

  showModal() {
    const modal = new bootstrap.Modal(this.modalTarget)
    modal.show()
  }

  downloadImage(event) {
    const currentImage = this.imagesValue[this.currentIndexValue]
    if (!currentImage) return

    // Create a temporary link to trigger download
    const link = document.createElement('a')
    link.href = currentImage.download_url
    link.download = currentImage.filename
    link.style.display = 'none'
    
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }

  // Keyboard navigation
  keyPressed(event) {
    if (!this.modalTarget.classList.contains('show')) return

    switch(event.key) {
      case 'ArrowLeft':
        event.preventDefault()
        this.previousImage()
        break
      case 'ArrowRight':
        event.preventDefault()
        this.nextImage()
        break
      case 'Escape':
        event.preventDefault()
        const modal = bootstrap.Modal.getInstance(this.modalTarget)
        if (modal) modal.hide()
        break
    }
  }

  // Touch/swipe support for mobile
  touchStart(event) {
    this.startX = event.touches[0].clientX
  }

  touchEnd(event) {
    if (!this.startX) return

    const endX = event.changedTouches[0].clientX
    const diffX = this.startX - endX

    if (Math.abs(diffX) > 50) { // Minimum swipe distance
      if (diffX > 0) {
        // Swipe left - next image
        this.nextImage()
      } else {
        // Swipe right - previous image
        this.previousImage()
      }
    }

    this.startX = null
  }
}