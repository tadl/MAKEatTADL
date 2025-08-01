# app/helpers/portal_helper.rb
module PortalHelper
  include Pagy::Frontend

  def bootstrap_status_badge(status)
    # Define status->class mapping
    badge_classes = {
      'pending'             => 'bg-warning text-dark',
      'information_requested'=> 'bg-danger text-white',
      'response_received'   => 'bg-info text-white',
      'approved'            => 'bg-dark text-white',
      'in_progress'         => 'bg-primary text-white',
      'ready_for_pickup'    => 'bg-success text-white',
      'archived'            => 'bg-secondary text-white',
      'ongoing'             => 'bg-light text-dark',
      'cancelled'           => 'bg-secondary text-white',
      'rejected'            => 'bg-danger text-white',
      'abandoned'           => 'bg-light text-muted',
    }

    klass = badge_classes[status.code] || 'bg-dark text-white'

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
