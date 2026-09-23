class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Staff-only app. When STAFF_PASSWORD is set (it is in production), every
  # page sits behind HTTP basic auth. Real per-person accounts are in FUTURE.md.
  if ENV["STAFF_PASSWORD"].present?
    http_basic_authenticate_with name: ENV.fetch("STAFF_USERNAME", "staff"), password: ENV["STAFF_PASSWORD"]
  end

  rescue_from ActiveRecord::RecordNotFound do
    render plain: "Not found", status: :not_found
  end
end
