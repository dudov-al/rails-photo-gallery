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
    this.showUploadProgress(files)
    
    // Create progress tracking for each file
    const uploadPromises = files.map((file, index) => this.uploadFileWithProgress(file, index))
    
    try {
      const results = await Promise.allSettled(uploadPromises)
      
      // Process results
      const successful = results.filter(r => r.status === 'fulfilled').length
      const failed = results.filter(r => r.status === 'rejected').length
      
      if (successful > 0) {
        this.showToast(`Successfully uploaded ${successful} image${successful > 1 ? 's' : ''}`, 'success')
      }
      
      if (failed > 0) {
        this.showToast(`Failed to upload ${failed} image${failed > 1 ? 's' : ''}`, 'error')
      }
      
    } catch (error) {
      console.error('Error uploading files:', error)
      this.showToast('Upload process encountered errors', 'error')
    } finally {
      setTimeout(() => {
        this.hideUploadProgress()
      }, 2000) // Keep progress visible briefly for user feedback
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

  // Enhanced upload with progress tracking
  async uploadFileWithProgress(file, index) {
    return new Promise((resolve, reject) => {
      const formData = new FormData()
      formData.append('image[file]', file)
      
      const xhr = new XMLHttpRequest()
      
      // Set up progress tracking
      xhr.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable) {
          const percentComplete = Math.round((event.loaded / event.total) * 100)
          this.updateUploadProgress(index, percentComplete, 'uploading')
        }
      })
      
      // Handle completion
      xhr.addEventListener('load', () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            const response = JSON.parse(xhr.responseText)
            
            if (response.status === 'success') {
              this.updateUploadProgress(index, 100, 'processing')
              this.addImagePreview(response.image)
              this.processingImages.add(response.image.id)
              resolve(response)
            } else {
              this.updateUploadProgress(index, 0, 'failed', response.errors?.join(', ') || 'Upload failed')
              reject(new Error(response.errors?.join(', ') || 'Upload failed'))
            }
          } catch (error) {
            this.updateUploadProgress(index, 0, 'failed', 'Invalid server response')
            reject(error)
          }
        } else {
          this.updateUploadProgress(index, 0, 'failed', `HTTP ${xhr.status}: ${xhr.statusText}`)
          reject(new Error(`HTTP ${xhr.status}: ${xhr.statusText}`))
        }
      })
      
      // Handle errors
      xhr.addEventListener('error', () => {
        this.updateUploadProgress(index, 0, 'failed', 'Network error occurred')
        reject(new Error('Network error occurred'))
      })
      
      xhr.addEventListener('timeout', () => {
        this.updateUploadProgress(index, 0, 'failed', 'Upload timeout')
        reject(new Error('Upload timeout'))
      })
      
      // Configure request
      xhr.open('POST', `/galleries/${this.galleryIdValue}/images`)
      xhr.setRequestHeader('X-CSRF-Token', document.querySelector('meta[name="csrf-token"]').content)
      xhr.timeout = 120000 // 2 minute timeout
      
      // Start upload
      xhr.send(formData)
    })
  }

  // Enhanced upload progress display
  showUploadProgress(files) {
    if (this.hasProgressTarget) {
      this.progressTarget.classList.remove('d-none')
    }
    
    // Create progress container if it doesn't exist
    let progressContainer = this.element.querySelector('.upload-progress-container')
    if (!progressContainer) {
      progressContainer = document.createElement('div')
      progressContainer.className = 'upload-progress-container'
      progressContainer.innerHTML = `
        <div class="d-flex justify-content-between align-items-center mb-3">
          <h6 class="mb-0">Upload Progress</h6>
          <button type="button" class="btn btn-sm btn-outline-secondary" data-action="click->image-upload#cancelAllUploads">
            Cancel All
          </button>
        </div>
        <div class="upload-files-list" data-image-upload-target="uploadFilesList"></div>
      `
      
      // Insert after drop zone
      const dropZone = this.dropZoneTarget
      dropZone.parentNode.insertBefore(progressContainer, dropZone.nextSibling)
    }
    
    // Create file progress items
    const filesList = progressContainer.querySelector('.upload-files-list')
    filesList.innerHTML = ''
    
    files.forEach((file, index) => {
      const fileItem = document.createElement('div')
      fileItem.className = 'upload-file-item'
      fileItem.dataset.fileIndex = index
      
      fileItem.innerHTML = `
        <div class="file-info">
          <div class="file-name" title="${file.name}">${file.name}</div>
          <div class="file-size">${this.formatFileSize(file.size)}</div>
        </div>
        <div class="upload-progress-bar">
          <div class="progress-fill" style="width: 0%"></div>
        </div>
        <div class="upload-status uploading">
          <svg class="status-icon spinning" viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <path d="M21 12a9 9 0 11-6.219-8.56"/>
          </svg>
          <span class="status-text">Queued</span>
        </div>
        <div class="upload-percentage">0%</div>
      `
      
      filesList.appendChild(fileItem)
    })
  }

  updateUploadProgress(fileIndex, percentage, status, errorMessage = null) {
    const fileItem = this.element.querySelector(`[data-file-index="${fileIndex}"]`)
    if (!fileItem) return
    
    const progressFill = fileItem.querySelector('.progress-fill')
    const statusElement = fileItem.querySelector('.upload-status')
    const statusIcon = fileItem.querySelector('.status-icon')
    const statusText = fileItem.querySelector('.status-text')
    const percentageElement = fileItem.querySelector('.upload-percentage')
    
    // Update progress bar
    if (progressFill) {
      progressFill.style.width = `${percentage}%`
    }
    
    // Update percentage display
    if (percentageElement) {
      percentageElement.textContent = `${percentage}%`
    }
    
    // Update status
    if (statusElement) {
      statusElement.className = `upload-status ${status}`
    }
    
    // Update icon and text based on status
    switch (status) {
      case 'uploading':
        statusIcon.innerHTML = '<path d="M21 12a9 9 0 11-6.219-8.56"/>'
        statusIcon.classList.add('spinning')
        statusText.textContent = percentage === 0 ? 'Starting...' : 'Uploading'
        break
        
      case 'processing':
        statusIcon.innerHTML = '<path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>'
        statusIcon.classList.add('spinning')
        statusText.textContent = 'Processing'
        break
        
      case 'completed':
        statusIcon.innerHTML = '<polyline points="20,6 9,17 4,12"/>'
        statusIcon.classList.remove('spinning')
        statusText.textContent = 'Complete'
        break
        
      case 'failed':
        statusIcon.innerHTML = '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>'
        statusIcon.classList.remove('spinning')
        statusText.textContent = errorMessage || 'Failed'
        statusText.title = errorMessage || 'Upload failed'
        break
    }
  }

  hideUploadProgress() {
    const progressContainer = this.element.querySelector('.upload-progress-container')
    if (progressContainer) {
      progressContainer.style.opacity = '0.6'
      setTimeout(() => {
        progressContainer.remove()
      }, 1000)
    }
    
    if (this.hasProgressTarget) {
      this.progressTarget.classList.add('d-none')
    }
  }

  cancelAllUploads() {
    // Cancel any ongoing uploads
    this.uploadQueue = []
    
    // Hide progress immediately
    this.hideUploadProgress()
    
    // Show cancellation message
    this.showToast('Uploads cancelled', 'info')
  }

  // Enhanced drag and drop feedback
  handleDragOver(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.add('dragover')
    
    // Show visual feedback for file type validation
    const items = event.dataTransfer.items
    let validFiles = 0
    let invalidFiles = 0
    
    for (let i = 0; i < items.length; i++) {
      if (this.allowedTypesValue.includes(items[i].type)) {
        validFiles++
      } else {
        invalidFiles++
      }
    }
    
    // Update drop zone text based on validation
    const dropText = this.dropZoneTarget.querySelector('.upload-text')
    if (dropText) {
      if (invalidFiles > 0) {
        dropText.textContent = `${validFiles} valid files, ${invalidFiles} invalid files`
        this.dropZoneTarget.classList.add('drag-invalid')
      } else {
        dropText.textContent = `Drop ${validFiles} file${validFiles > 1 ? 's' : ''} to upload`
        this.dropZoneTarget.classList.remove('drag-invalid')
      }
    }
  }

  handleDragLeave(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.remove('dragover', 'drag-invalid')
    
    // Reset drop zone text
    const dropText = this.dropZoneTarget.querySelector('.upload-text')
    if (dropText) {
      dropText.textContent = 'Drop images here or click to browse'
    }
  }

  // Utility methods
  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  showToast(message, type) {
    // Delegate to loading controller if available
    const loadingController = this.application.getControllerForElementAndIdentifier(document.body, "loading")
    if (loadingController) {
      loadingController.showToast(message, type)
    } else {
      // Fallback to simple alert
      if (type === 'error') {
        this.showError(message)
      }
    }
  }

  // Network retry logic for failed uploads
  async retryUpload(fileIndex, file) {
    try {
      this.updateUploadProgress(fileIndex, 0, 'uploading')
      await this.uploadFileWithProgress(file, fileIndex)
    } catch (error) {
      console.error('Retry upload failed:', error)
      this.updateUploadProgress(fileIndex, 0, 'failed', 'Retry failed')
    }
  }