import { Controller } from "@hotwired/stimulus"
import Sortable from 'sortablejs'

// Connects to data-controller="image-manager"
export default class extends Controller {
  static targets = ["imageContainer", "selectedCount", "bulkActions"]
  static values = { galleryId: Number }

  connect() {
    this.selectedImages = new Set()
    this.setupSortable()
    this.setupBulkSelection()
  }

  setupSortable() {
    if (this.hasImageContainerTarget) {
      this.sortable = Sortable.create(this.imageContainerTarget, {
        animation: 200,
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        handle: '.drag-handle',
        onEnd: this.handleReorder.bind(this)
      })
    }
  }

  setupBulkSelection() {
    // Add event delegation for image selection
    this.imageContainerTarget.addEventListener('change', (event) => {
      if (event.target.matches('.image-checkbox')) {
        this.handleImageSelection(event)
      }
    })

    // Add select all functionality
    const selectAllCheckbox = document.querySelector('#select-all-images')
    if (selectAllCheckbox) {
      selectAllCheckbox.addEventListener('change', this.toggleSelectAll.bind(this))
    }
  }

  async handleReorder(event) {
    const imageElements = Array.from(this.imageContainerTarget.children)
    const imageIds = imageElements.map(element => 
      parseInt(element.dataset.imageId)
    ).filter(id => !isNaN(id))

    try {
      const response = await fetch(`/galleries/${this.galleryIdValue}/images/reorder`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ image_ids: imageIds })
      })

      const data = await response.json()

      if (!response.ok || data.status !== 'success') {
        this.showError('Failed to reorder images')
        // Revert the DOM changes if the request failed
        this.revertOrder(event.oldIndex, event.newIndex)
      }
    } catch (error) {
      console.error('Reorder error:', error)
      this.showError('Failed to reorder images')
      this.revertOrder(event.oldIndex, event.newIndex)
    }
  }

  revertOrder(oldIndex, newIndex) {
    // Revert the DOM changes by moving the element back
    const items = Array.from(this.imageContainerTarget.children)
    const item = items[newIndex]
    
    if (oldIndex < newIndex) {
      this.imageContainerTarget.insertBefore(item, items[oldIndex])
    } else {
      this.imageContainerTarget.insertBefore(item, items[oldIndex + 1])
    }
  }

  handleImageSelection(event) {
    const checkbox = event.target
    const imageId = parseInt(checkbox.dataset.imageId)
    const imageCard = checkbox.closest('[data-image-id]')

    if (checkbox.checked) {
      this.selectedImages.add(imageId)
      imageCard.classList.add('selected')
    } else {
      this.selectedImages.delete(imageId)
      imageCard.classList.remove('selected')
    }

    this.updateBulkActionsUI()
  }

  toggleSelectAll(event) {
    const selectAll = event.target.checked
    const checkboxes = this.imageContainerTarget.querySelectorAll('.image-checkbox')
    
    checkboxes.forEach(checkbox => {
      const imageId = parseInt(checkbox.dataset.imageId)
      const imageCard = checkbox.closest('[data-image-id]')
      
      checkbox.checked = selectAll
      
      if (selectAll) {
        this.selectedImages.add(imageId)
        imageCard.classList.add('selected')
      } else {
        this.selectedImages.delete(imageId)
        imageCard.classList.remove('selected')
      }
    })

    this.updateBulkActionsUI()
  }

  updateBulkActionsUI() {
    const count = this.selectedImages.size
    
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = count
    }

    if (this.hasBulkActionsTarget) {
      if (count > 0) {
        this.bulkActionsTarget.classList.remove('d-none')
      } else {
        this.bulkActionsTarget.classList.add('d-none')
      }
    }

    // Update select all checkbox state
    const selectAllCheckbox = document.querySelector('#select-all-images')
    const allCheckboxes = this.imageContainerTarget.querySelectorAll('.image-checkbox')
    
    if (selectAllCheckbox && allCheckboxes.length > 0) {
      const allSelected = Array.from(allCheckboxes).every(cb => cb.checked)
      const noneSelected = Array.from(allCheckboxes).every(cb => !cb.checked)
      
      selectAllCheckbox.checked = allSelected
      selectAllCheckbox.indeterminate = !allSelected && !noneSelected
    }
  }

  async bulkDelete() {
    if (this.selectedImages.size === 0) {
      return
    }

    const count = this.selectedImages.size
    if (!confirm(`Are you sure you want to delete ${count} selected image${count > 1 ? 's' : ''}?`)) {
      return
    }

    const imageIds = Array.from(this.selectedImages)

    try {
      const response = await fetch(`/galleries/${this.galleryIdValue}/images/bulk_destroy`, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ image_ids: imageIds })
      })

      const data = await response.json()

      if (response.ok && data.status === 'success') {
        // Remove deleted images from DOM
        imageIds.forEach(imageId => {
          const imageElement = this.imageContainerTarget.querySelector(`[data-image-id="${imageId}"]`)
          if (imageElement) {
            imageElement.remove()
          }
        })

        this.selectedImages.clear()
        this.updateBulkActionsUI()
        this.showSuccess(`${data.deleted_count} images deleted successfully`)
      } else {
        const errorMsg = data.errors ? data.errors.join(', ') : 'Failed to delete images'
        this.showError(errorMsg)
      }
    } catch (error) {
      console.error('Bulk delete error:', error)
      this.showError('Failed to delete images')
    }
  }

  clearSelection() {
    this.selectedImages.clear()
    
    const checkboxes = this.imageContainerTarget.querySelectorAll('.image-checkbox')
    checkboxes.forEach(checkbox => {
      checkbox.checked = false
      const imageCard = checkbox.closest('[data-image-id]')
      imageCard.classList.remove('selected')
    })

    this.updateBulkActionsUI()
  }

  showError(message) {
    // Create a temporary toast/alert for the error
    const alert = document.createElement('div')
    alert.className = 'alert alert-danger alert-dismissible fade show position-fixed'
    alert.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;'
    alert.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
    
    document.body.appendChild(alert)
    
    // Auto-dismiss after 5 seconds
    setTimeout(() => {
      if (alert.parentNode) {
        alert.remove()
      }
    }, 5000)
  }

  showSuccess(message) {
    const alert = document.createElement('div')
    alert.className = 'alert alert-success alert-dismissible fade show position-fixed'
    alert.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;'
    alert.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `
    
    document.body.appendChild(alert)
    
    setTimeout(() => {
      if (alert.parentNode) {
        alert.remove()
      }
    }, 3000)
  }
}