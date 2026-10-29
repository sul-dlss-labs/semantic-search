class ApplicationController < ActionController::Base
  # Adds a few additional behaviors into the application controller
  include Blacklight::Controller
  include Authentication
  layout :determine_layout if respond_to? :layout

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout "application"

  private

  # @return [Boolean] true if the document's text must be withheld from this user.
  def hide_restricted_text?(document)
    document.restricted? && !authenticated?
  end
  helper_method :hide_restricted_text?
end
