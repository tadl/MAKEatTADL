# app/helpers/portal_helper.rb
module PortalHelper
  def bootstrap_status_badge(status)
    klass = case status.code
    when 'pending'          then 'bg-warning text-dark'
    when 'info_requested'   then 'bg-danger text-white'
    when 'queued'           then 'bg-info text-white'
    when 'in_progress'      then 'bg-primary text-white'
    when 'ready_for_pickup' then 'bg-success text-white'
    when 'archived'         then 'bg-secondary text-white'
    when 'ongoing'          then 'bg-light text-dark'
    else                         'bg-dark text-white'
    end

    content_tag :span, status.name, class: "badge #{klass} px-3 py-2"
  end

  def author_display_name(author)
    if author.is_a?(StaffUser)
      #author.name.split(/\s+/).first
      "TADL Staff"
    else
      author.name
    end
  end
end
