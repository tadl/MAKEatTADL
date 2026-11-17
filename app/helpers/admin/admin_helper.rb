module Admin::AdminHelper
  def admin_icon(name, classes: "h-5 w-5")
    paths = {
      dashboard: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
      jobs: "M8 4H5a2 2 0 0 0-2 2v14h18V6a2 2 0 0 0-2-2h-3 M8 2h8v4H8z M7 11h10 M7 15h7",
      models: "m12 2 9 5v10l-9 5-9-5V7z M3 7l9 5 9-5 M12 12v10 M7.5 4.5l9 5",
      patrons: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M16 3a4 4 0 0 1 0 8 M22 21v-2a4 4 0 0 0-3-3.87 M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
      statistics: "M3 3v18h18 M7 16v-5 M12 16V6 M17 16V9",
      help: "M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3 M12 17h.01 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
      settings: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1z",
      arrow: "M5 12h14 M14 7l5 5-5 5",
      system: "M3 3h18v13H3z M8 21h8 M12 16v5",
      dark: "M20 15.2A9 9 0 0 1 8.8 4 9 9 0 1 0 20 15.2z",
      light: "M12 3v2 M12 19v2 M3 12h2 M19 12h2 M5.6 5.6 7 7 M17 17l1.4 1.4 M5.6 18.4 7 17 M17 7l1.4-1.4 M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
      density_normal: "M4 5h16v4H4z M4 15h16v4H4z",
      density_condensed: "M4 4h16v3H4z M4 10.5h16v3H4z M4 17h16v3H4z",
      menu: "M4 6h16 M4 12h16 M4 18h16"
    }
    tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 1.6,
            "stroke-linecap": "round", "stroke-linejoin": "round", class: classes, "aria-hidden": true) do
      tag.path(d: paths.fetch(name.to_sym, paths[:models]))
    end
  end

  def admin_navigation_link(label, path, icon:, active:)
    link_to path, class: "admin-nav-link", "aria-current": ("page" if active) do
      safe_join([admin_icon(icon), tag.span(label)])
    end
  end

  def admin_value(value)
    case value
    when true then "Yes"
    when false then "No"
    when Time, ActiveSupport::TimeWithZone then value.in_time_zone.strftime("%b %-d, %Y · %-I:%M %p")
    when Date then value.strftime("%b %-d, %Y")
    when Hash, Array then value.to_json
    else value.presence || "—"
    end
  end

  def admin_status_badge(status)
    color = case status&.code
    when "pending", "information_requested" then "bg-amber-50 text-amber-800"
    when "approved", "in_progress", "response_received" then "bg-sky-50 text-sky-800"
    when "ready_for_pickup" then "bg-accent-50 text-accent-700"
    else "bg-slate-100 text-slate-600"
    end
    tag.span(status&.name || "Unknown", class: "inline-flex items-center rounded-md px-2.5 py-1 text-xs font-medium #{color}")
  end

  def admin_pickup_confirmation(job, location_name: nil)
    price = if job.actual_cost.present?
      "Price: #{number_to_currency(job.actual_cost)}"
    elsif job.slicer_cost.present?
      "Estimated price: #{number_to_currency(job.slicer_cost)} (final price not recorded)"
    else
      "Price not recorded"
    end
    location_name ||= PickupLocation.find_by(code: job.pickup_location)&.name || job.pickup_location
    ["Mark job ##{job.id} as picked up?",
     "Patron: #{job.patron.name.presence || job.patron.email}",
     "Pickup location: #{location_name.presence || 'Not recorded'}",
     "Completed: #{job.completion_date&.strftime('%b %-d, %Y') || 'Not recorded'}",
     price, "", "This sets today’s pickup date and archives the job."].join("\n")
  end

  def admin_pagination_pages(current_page:, total_pages:)
    pages = ((1..[3, total_pages].min).to_a +
      ([current_page - 2, 1].max..[current_page + 2, total_pages].min).to_a +
      ([total_pages - 2, 1].max..total_pages).to_a).uniq.sort
    pages.each_with_object([]) do |page, result|
      previous = result.last
      if previous && page > previous + 1
        result << (page == previous + 2 ? previous + 1 : nil)
      end
      result << page
    end
  end

  def admin_pagination_path(page)
    query = request.query_parameters.merge("page" => page, "per_page" => @per_page)
    "#{request.path}?#{query.to_query}"
  end

  def admin_pagination_hidden_fields
    query = request.query_parameters.except("page", "per_page").to_query
    safe_join(URI.decode_www_form(query).map { |name, value| hidden_field_tag(name, value, id: nil) })
  end

  def admin_avatar_url(user)
    value = user.avatar_url.to_s.strip
    uri = URI.parse(value)
    value if uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end

  def admin_user_initials(user)
    (user.name.presence || user.email).split.first(2).map { |part| part.first }.join.upcase
  end
end
