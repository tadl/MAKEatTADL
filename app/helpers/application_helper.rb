# app/helpers/application_helper.rb
module ApplicationHelper
  # Pages where we hide both breadcrumb & logout
  PUBLIC_PAGES = {
    'portal'  => %w[
      home
      submit_print create_print_job
      submit_scan  create_scan_job
      token_request send_token
      token_thank_you thank_you
    ]
  }.freeze

  # Returns an Array of crumb hashes: { name:, path: (optional) }
  def breadcrumb_items
    return [] if PUBLIC_PAGES[controller_name]&.include?(action_name)

    items = []
    items << { name: 'Home', path: root_path }

    if controller_name == 'portal'
      case action_name
      when 'dashboard'
        items << { name: 'Dashboard' }
      when 'show', 'create_message'
        items << { name: 'Dashboard', path: dashboard_path }
        items << { name: 'Details' }
      end
    end

    items
  end

  # Should we hide the breadcrumb entirely?
  def hide_breadcrumb?
    PUBLIC_PAGES[controller_name]&.include?(action_name)
  end

  # Should we hide the logout button?
  def hide_logout?
    # hide on exactly the “public” portal pages (including home)
    PUBLIC_PAGES[controller_name]&.include?(action_name)
  end
end
