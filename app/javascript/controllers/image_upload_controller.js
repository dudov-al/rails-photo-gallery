import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="image-upload"
export default class extends Controller {
  static targets = ["input", "preview", "dropZone", "progress", "error", "processingStatus"]
  static values = { 
    galleryId: Number,
    maxSize: { type: Number, default: 50 * 1024 * 1024 }, // 50MB
    allowedTypes: { type: Array, default: ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif'] },
    processingCheckInterval: { type: Number, default: 3000 } // 3 seconds
  }

  connect() {
    this.setupDragAndDrop()
    this.uploadQueue = []
    this.processingImages = new Set()
    this.processingTimer = null
    this.startProcessingMonitor()
  }

  disconnect() {
    if (this.processingTimer) {
      clearInterval(this.processingTimer)
    }
  }

  setupDragAndDrop() {
    const dropZone = this.dropZoneTarget

    dropZone.addEventListener('dragover', this.handleDragOver.bind(this))
    dropZone.addEventListener('dragleave', this.handleDragLeave.bind(this))
    dropZone.addEventListener('drop', this.handleDrop.bind(this))
  }

  handleDragOver(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.add('border-primary', 'bg-light')
  }

  handleDragLeave(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove('border-primary', 'bg-light')
  }

  handleDrop(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove('border-primary', 'bg-light')
    
    const files = event.dataTransfer.files
    this.handleFiles(files)
  }

  selectFiles() {
    this.inputTarget.click()
  }

  fileSelected() {
    const files = this.inputTarget.files
    this.handleFiles(files)
  }

  handleFiles(files) {
    if (files.length === 0) return

    this.showProgress()
    this.hideError()

    // Validate all files first
    const validFiles = []
    const errors = []

    for (let i = 0; i < files.length; i++) {
      const file = files[i]
      const validation = this.validateFile(file)
      
      if (validation.valid) {
        validFiles.push(file)
      } else {
        errors.push(`${file.name}: ${validation.error}`)
      }
    }

    // Show validation errors
    if (errors.length > 0) {
      this.showError(errors.join('\n'))
    }

    // Upload valid files
    if (validFiles.length > 0) {
      this.uploadMultipleFiles(validFiles)
    } else {
      this.hideProgress()
    }
  }

  validateFile(file) {
    if (!this.allowedTypesValue.includes(file.type)) {
      return { valid: false, error: 'Invalid file type. Please upload images only.' }
    }

    if (file.size > this.maxSizeValue) {
      const maxSizeMB = Math.round(this.maxSizeValue / (1024 * 1024))
      return { valid: false, error: `File too large. Maximum size is ${maxSizeMB}MB.` }
    }

    return { valid: true }
  }

  async uploadMultipleFiles(files) {
    this.uploadQueue = [...files]
    const uploadPromises = files.map(file => this.uploadFile(file))
    
    try {
      await Promise.allSettled(uploadPromises)
    } catch (error) {
      console.error('Error uploading files:', error)
    } finally {
      this.hideProgress()
      this.uploadQueue = []
    }
  }

  async uploadFile(file) {
    const formData = new FormData()
    formData.append('image[file]', file)

    try {
      const response = await fetch(`/galleries/${this.galleryIdValue}/images`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      const data = await response.json()

      if (response.ok && data.status === 'success') {
        this.addImagePreview(data.image)
        this.processingImages.add(data.image.id)
      } else {
        const errorMsg = data.errors ? data.errors.join(', ') : 'Upload failed'
        this.showError(`${file.name}: ${errorMsg}`)
      }
    } catch (error) {
      console.error('Upload error:', error)
      this.showError(`${file.name}: Upload failed. Please try again.`)
    }
  }

  addImagePreview(imageData) {
    const processingStatus = imageData.processing_status || 'pending'
    const isProcessing = processingStatus !== 'completed'
    const thumbnailUrl = imageData.thumbnail_url || this.getPlaceholderImage()
    
    const previewHTML = `
      <div class="col-md-3 mb-3" data-image-id="${imageData.id}">
        <div class="card ${isProcessing ? 'border-warning' : ''}">
          <div class="position-relative">
            <img src="${thumbnailUrl}" class="card-img-top" alt="${imageData.filename}" 
                 style="${isProcessing ? 'opacity: 0.7;' : ''}">
            ${isProcessing ? `
              <div class="position-absolute top-50 start-50 translate-middle">
                <div class="spinner-border text-primary" role="status">
                  <span class="visually-hidden">Processing...</span>
                </div>
              </div>
            ` : ''}
          </div>
          <div class="card-body p-2">
            <p class="card-text small mb-1">${imageData.filename}</p>
            ${imageData.file_size ? `<p class="text-muted small mb-1">${imageData.file_size}</p>` : ''}
            ${imageData.dimensions ? `<p class="text-muted small mb-1">${imageData.dimensions}</p>` : ''}
            <div class="processing-status small mb-2" data-status="${processingStatus}">
              ${this.getProcessingStatusText(processingStatus)}
            </div>
            <div class="btn-group w-100" role="group">
              <button class="btn btn-sm btn-outline-primary" data-action="click->image-upload#editImage" data-image-id="${imageData.id}">
                Edit
              </button>
              <button class="btn btn-sm btn-danger" data-action="click->image-upload#deleteImage" data-image-id="${imageData.id}">
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    `
    
    this.previewTarget.insertAdjacentHTML('beforeend', previewHTML)
  }

  getProcessingStatusText(status) {
    const statusText = {
      'pending': '<span class="badge bg-warning">Processing Queue</span>',
      'processing': '<span class="badge bg-info">Processing...</span>',
      'completed': '<span class="badge bg-success">Ready</span>',
      'failed': '<span class="badge bg-danger">Failed</span>',
      'retrying': '<span class="badge bg-warning">Retrying...</span>'
    }
    return statusText[status] || '<span class="badge bg-secondary">Unknown</span>'
  }

  getPlaceholderImage() {
    // Return a placeholder image for when thumbnails aren't ready yet
    return 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzAwIiBoZWlnaHQ9IjMwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8cmVjdCB3aWR0aD0iMzAwIiBoZWlnaHQ9IjMwMCIgZmlsbD0iI2Y4ZjlmYSIgc3Ryb2tlPSIjZGVlMmU2IiBzdHJva2Utd2lkdGg9IjEiLz4KICA8dGV4dCB4PSI1MCUiIHk9IjUwJSIgZm9udC1mYW1pbHk9IkFyaWFsLCBzYW5zLXNlcmlmIiBmb250LXNpemU9IjE4IiBmaWxsPSIjNmM3NTdkIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBkeT0iLjNlbSI+UHJvY2Vzc2luZy4uLjwvdGV4dD4KPC9zdmc+'
  }

  async deleteImage(event) {
    const imageId = event.target.dataset.imageId
    const imageElement = event.target.closest('[data-image-id]')

    if (!confirm('Are you sure you want to delete this image?')) {
      return
    }

    try {
      const response = await fetch(`/galleries/${this.galleryIdValue}/images/${imageId}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      const data = await response.json()

      if (response.ok && data.status === 'success') {
        imageElement.remove()
        this.processingImages.delete(parseInt(imageId))
      } else {
        this.showError('Failed to delete image')
      }
    } catch (error) {
      console.error('Delete error:', error)
      this.showError('Failed to delete image')
    }
  }

  editImage(event) {
    const imageId = event.target.dataset.imageId
    // TODO: Implement edit modal or inline editing
    console.log(`Edit image ${imageId}`)
  }

  // Processing status monitoring
  startProcessingMonitor() {
    this.processingTimer = setInterval(() => {
      if (this.processingImages.size > 0) {
        this.checkProcessingStatus()
      }
    }, this.processingCheckIntervalValue)
  }

  async checkProcessingStatus() {
    try {
      const response = await fetch(`/galleries/${this.galleryIdValue}/images/processing_status`, {
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.updateProcessingStatus(data.processing_images)
      }
    } catch (error) {
      console.error('Processing status check failed:', error)
    }
  }

  updateProcessingStatus(processingImages) {
    processingImages.forEach(imageData => {
      const imageElement = this.previewTarget.querySelector(`[data-image-id="${imageData.id}"]`)
      if (!imageElement) return

      const statusElement = imageElement.querySelector('.processing-status')
      const cardElement = imageElement.querySelector('.card')
      const imgElement = imageElement.querySelector('img')
      const spinnerContainer = imageElement.querySelector('.position-absolute')

      // Update status badge
      if (statusElement) {
        statusElement.innerHTML = this.getProcessingStatusText(imageData.processing_status)
        statusElement.dataset.status = imageData.processing_status
      }

      // Handle completed processing
      if (imageData.processing_status === 'completed') {
        this.processingImages.delete(imageData.id)
        
        // Remove processing styling
        cardElement.classList.remove('border-warning')
        imgElement.style.opacity = '1'
        
        // Remove spinner
        if (spinnerContainer) {
          spinnerContainer.remove()
        }

        // Update thumbnail if available
        // Note: In a real implementation, you'd fetch the updated image data
        // to get the actual thumbnail URL
      }

      // Handle failed processing
      if (imageData.processing_status === 'failed') {
        cardElement.classList.remove('border-warning')
        cardElement.classList.add('border-danger')
        
        if (spinnerContainer) {
          spinnerContainer.innerHTML = `
            <i class="fas fa-exclamation-triangle text-danger fs-2"></i>
          `
        }
      }
    })
  }

  showProgress() {
    if (this.hasProgressTarget) {
      this.progressTarget.classList.remove('d-none')
    }
  }

  hideProgress() {
    if (this.hasProgressTarget) {
      this.progressTarget.classList.add('d-none')
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove('d-none')
    }
  }

  hideError() {
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add('d-none')
    }
  }
}