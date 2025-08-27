// Import and register all your controllers from the importmap under controllers/*

import { application } from "controllers/application"

// Import specific controllers
import AuthFormController from "./auth_form_controller"
import GalleryFormController from "./gallery_form_controller"
import GalleryViewerController from "./gallery_viewer_controller"
import ImageManagerController from "./image_manager_controller"
import ImageUploadController from "./image_upload_controller"
import OptimizedGalleryController from "./optimized_gallery_controller"
import PasswordFormController from "./password_form_controller"
import PublicGalleryController from "./public_gallery_controller"

// Import new enhanced controllers
import LoadingController from "./loading_controller"
import GalleryDashboardController from "./gallery_dashboard_controller"

// Register controllers
application.register("auth-form", AuthFormController)
application.register("gallery-form", GalleryFormController)
application.register("gallery-viewer", GalleryViewerController)
application.register("image-manager", ImageManagerController)
application.register("image-upload", ImageUploadController)
application.register("optimized-gallery", OptimizedGalleryController)
application.register("password-form", PasswordFormController)
application.register("public-gallery", PublicGalleryController)

// Register enhanced controllers
application.register("loading", LoadingController)
application.register("gallery-dashboard", GalleryDashboardController)

// Eager load all other controllers defined in the import map under controllers/**/*_controller
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// Lazy load controllers as they appear in the DOM (remember not to preload controllers in import map!)
// import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
// lazyLoadControllersFrom("controllers", application)