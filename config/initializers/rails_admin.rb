# config/initializers/rails_admin.rb
require Rails.root.join('lib/rails_admin/config/actions/conversation')

RailsAdmin.config do |config|
  config.authorize_with :cancancan, Ability
  # ─ Authentication & inheritance ───────────────────────
  config.parent_controller      = '::ApplicationController'
  config.authenticate_with do
    redirect_to '/auth/google_oauth2' unless current_staff_user
  end
  config.current_user_method(&:current_staff_user)

  config.asset_source           = :sprockets
  config.default_items_per_page = 10

  # ─ App name & included models ────────────────────────
  config.main_app_name   = ['MAKE', 'Things at TADL']
  config.included_models = %w[
    StaffUser
    Patron
    Job
    Status
    Printer
    PrintType
    FilamentColor
    PickupLocation
    Category
    Conversation
    Message
    PrintableModel
    Audited::Audit
  ]

  # ─ Actions ────────────────────────────────────────────
  config.actions do
    dashboard                     # mandatory
    index                         # mandatory
    new   { except ['StaffUser'] }
    export
    bulk_delete do
      visible { bindings[:controller].current_staff_user.admin? }
    end
    show

    # custom Conversation button on Jobs
    conversation do
      only ['Job']
    end

    edit do
      visible do
        bindings[:controller].current_ability.can?(:update, bindings[:abstract_model].model)
      end
    end

    delete do
      visible do
        bindings[:controller].current_ability.can?(:destroy, bindings[:abstract_model].model)
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  #   Management (only Jobs)
  # ─────────────────────────────────────────────────────────
  config.model 'Job' do
    navigation_label 'Management'
    weight           100
    label_plural     'Jobs'

    list do
      scopes [:active, :inactive, :ongoing]
      sort_by :created_at
      field :patron
      field :status, :belongs_to_association do
        label        'Status'
        pretty_value { bindings[:object].status.name }
        filterable   true
        filter_options { Status.all.map { |s| [s.name, s.id] } }
      end
      field :category, :belongs_to_association do
        pretty_value { bindings[:object].category.name }
      end
      field :type, :enum do
        label          'Job Type'
        enum           { [['Print','PrintJob'], ['Scan','ScanJob']] }
        filterable     true
        filter_options { [['Print','PrintJob'], ['Scan','ScanJob']] }
        pretty_value   { value == 'PrintJob' ? 'Print' : 'Scan' }
      end
      field :pickup_location
      field :assigned_printer do
        label 'Assigned Printer'
      end
      field :created_at
    end

    show do
      field :id
      field :patron
      field :status, :belongs_to_association do
        label        'Status'
        pretty_value { bindings[:object].status.name }
      end
      field :category, :belongs_to_association do
        pretty_value { bindings[:object].category.name }
      end
      field :type do
        label 'Job Type'
      end
      field :notes
      field :model_file, :active_storage do
        label 'Model File'
        pretty_value do
          attachment = bindings[:object].model_file
          if attachment.attached?
            blob = attachment.blob
            # Link to download the file, showing the original filename
            bindings[:view].link_to \
              blob.filename.to_s,
              Rails.application.routes.url_helpers.rails_blob_path(attachment, disposition: 'attachment', only_path: true)
          else
            bindings[:view].content_tag(:em, 'No file uploaded')
          end
        end
      end

      group :print_fields do
        label   'Print Details'
        visible { bindings[:object].is_a?(PrintJob) }
        field :print_type, :belongs_to_association do
          label          'Print Type'
          pretty_value   { bindings[:object].print_type&.name }
          filterable     true
          associated_collection_scope { ->(scope){ scope.order(:position) } }
        end
        field :url
        field :filament_color
        field :print_time_estimate
        field :slicer_weight
        field :slicer_cost
        field :actual_weight
        field :resin_volume_ml do
          label "Resin Volume (mL)"
        end
        field :actual_cost
        field :completion_date
        field :assigned_printer
      end

      group :scan_fields do
        label   'Scan Details'
        visible { bindings[:object].is_a?(ScanJob) }
        field :scan_image, :active_storage do
          label 'Submitted Photo'
          pretty_value do
            img = bindings[:object].scan_image
            if img.attached?
              thumb = bindings[:view].image_tag(
                img.variant(resize_to_limit: [300,300]),
                class: 'rounded shadow',
                style: 'margin:4px;max-width:300px;'
              )
              blob_url = Rails.application.routes.url_helpers.
                           rails_blob_path(img, disposition: 'attachment', only_path: true)
              bindings[:view].link_to(thumb, blob_url, target: '_blank', rel: 'noopener')
            else
              bindings[:view].content_tag(:em, 'No photo uploaded.')
            end
          end
        end
        field :spray_ok
      end

      field :pickup_location
      field :created_at
      field :updated_at
    end

    edit do
      field :patron do
        inline_add   { bindings[:controller].current_staff_user.admin? }
        inline_edit  { bindings[:controller].current_staff_user.admin? }
        help ''
      end
      field :status, :belongs_to_association do
        label 'Status'
        associated_collection_scope { ->(scope){ scope.order(:position) } }
        inline_add   { bindings[:controller].current_staff_user.admin? }
        inline_edit  { bindings[:controller].current_staff_user.admin? }
        help ''
      end
      field :category, :belongs_to_association do
        label 'Category'
        associated_collection_scope { ->(scope){ scope.order(:position) } }
        inline_add   { bindings[:controller].current_staff_user.admin? }
        inline_edit  { bindings[:controller].current_staff_user.admin? }
        help ''
      end
      field :type, :enum do
        label         'Job Type'
        enum          { [['Print','PrintJob'], ['Scan','ScanJob']] }
        default_value { bindings[:object].type || 'PrintJob' }
        help ''
      end
      field :pickup_location, :enum do
        label    'Pickup Location'
        required true
        enum     { PickupLocation.where(active: true).order(:position).pluck(:name, :code) }
        help ''
      end
      field :notes do
        help 'Notes from requestor. Print jobs for Asssitive/Fidget categories will include relevant contact method/info and/or company/organization information here.'
      end
      field :model_file, :active_storage do
        label 'Model File'
        pretty_value do
          attachment = bindings[:object].model_file
          if attachment.attached?
            blob = attachment.blob
            # Link to download the file, showing the original filename
            bindings[:view].link_to \
              blob.filename.to_s,
              Rails.application.routes.url_helpers.rails_blob_path(attachment, disposition: 'attachment', only_path: true)
          else
            bindings[:view].content_tag(:em, 'No file uploaded')
          end
        end
        help ''
      end

      group :print_fields do
        label   'Print-only fields'
        visible { bindings[:object].is_a?(PrintJob) }
        field :assigned_printer, :belongs_to_association do
          inline_add   { bindings[:controller].current_staff_user.admin? }
          inline_edit  { bindings[:controller].current_staff_user.admin? }
          associated_collection_scope { ->(scope){ scope.order(:name) } }
          help 'The printer that will be used for this job.'
        end
        field :print_type, :belongs_to_association do
          inline_add   { bindings[:controller].current_staff_user.admin? }
          inline_edit  { bindings[:controller].current_staff_user.admin? }
          label                         'Print Type'
          associated_collection_scope   { ->(scope){ scope.order(:position) } }
          help 'Automatically set from the assigned printer.'
        end
        field :url do
          label 'URL'
          help 'A URL is provided by the requestor when a model file is not.'
        end
        field :filament_color, :enum do
          enum          { FilamentColor.order(:name).pluck(:name, :code) }
          default_value { bindings[:object].filament_color }
          help ''
        end
        field :quantity, :integer do
          label "Quantity"
          help "Number of copies printed. Update this when printing additional copies."
        end
        field :print_time_estimate do
          help 'Estimated print duration from slicer.'
        end
        field :slicer_weight do
          label "Weight estimate (grams)"
          help 'Estimated weight from slicer.'
        end
        field :slicer_cost do
          help 'Estimated cost, derived from estimated weight.'
        end
        field :resin_volume_ml do
          label "Resin Volume (mL)"
          help  "How many milliliters of resin were used?"
        end
        field :actual_weight do
          label "Weight (grams)"
          help "How many grams is the finished print?"
        end
        field :actual_cost do
          help 'When a value is entered here, the patron will be notified their print is ready to pick up.'
        end
        field :completion_date, :date do
          help 'Set this when the print is picked up.'
        end
      end

      group :scan_fields do
        label   'Scan-only fields'
        visible { bindings[:object].is_a?(ScanJob) }
        field :scan_image, :active_storage do
          label 'Submitted Photo'
          help  'Upload one photo (replaces the existing image)'
        end
        field :spray_ok
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  #   Form Options (for your public webforms)
  # ─────────────────────────────────────────────────────────
  config.model 'FilamentColor' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Form Options'
    weight           200
    label_plural     'Filament Colors'

    list do
      scopes [nil, :active]
      sort_by :name
      field :name
      field :code
      field :active
    end

    edit do
      field :name
      field :code
      field :active
    end
  end

  config.model 'PrintableModel' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Form Options'
    weight           210
    label_plural     'Printable Models'

    list do
      sort_by :name
      field :name
      field :code
      field :category
    end

    edit do
      field :name
      field :code
      field :position
      field :category
      field :notes

      field :model_file, :active_storage do
        label 'Model File (STL)'
        help  'Attach the .stl file for this model'
      end

      field :preview_image , :active_storage do
        label 'Photo'
        help  'Attach a PNG/JPG preview for this model'
      end
    end
  end

  config.model 'PickupLocation' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Form Options'
    weight           220
    label_plural     'Pickup Locations'

    list do
      sort_by :name
      field :name
      field :code
      field :active
      field :scanner
      field :fdm_printer
      field :resin_printer
    end

    edit do
      field :name
      field :code
      field :active
      field :scanner, :boolean do
        help "Check if this location has a 3D scanner"
      end
      field :fdm_printer, :boolean do
        help "Check if this location has an FDM printer"
      end
      field :resin_printer, :boolean do
        help "Check if this location has a resin printer"
      end
      field :printers, :has_many_association do
        label 'Printers at this Location'
        help  'Select which printers live at this pickup location'
        inline_add  { bindings[:controller].current_staff_user.admin? }
        inline_edit { bindings[:controller].current_staff_user.admin? }
        associated_collection_scope { ->(scope){ scope.order(:name) } }
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  #   Admin (everything staff/admin manage)
  # ─────────────────────────────────────────────────────────
  config.model 'Audited::Audit' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           299
    label_plural 'Activity Log'
    list do
      field :created_at
      field :user         # who made the change
      field :auditable    # record that was changed
      field :action       # update/create/destroy
      field :audited_changes
    end
    show do
      include_all_fields
    end
  end

  config.model 'Printer' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           300
    label_plural     'Printers'

    list do
      sort_by :name
      field :id
      field :name
      field :pickup_location
      field :print_type
      field :printer_model
      field :bed_size
      field :location
    end

    show do
      field :id
      field :name
      field :pickup_location
      field :print_type
      field :printer_model
      field :bed_size
      field :location
      field :created_at
      field :updated_at
    end

    edit do
      field :name
      field :pickup_location, :belongs_to_association do
        label           'Pickup Location'
        inline_add      { bindings[:controller].current_staff_user.admin? }
        inline_edit     { bindings[:controller].current_staff_user.admin? }
        associated_collection_scope { ->(scope){ scope.order(:name) } }
      end
      field :print_type, :belongs_to_association do
        label           'Print Type'
        inline_add      true
        inline_edit     true
        associated_collection_scope { ->(scope){ scope.order(:position) } }
      end
      field :printer_model
      field :bed_size, :string do
        help 'e.g. 200x200x200 mm'
      end
      field :location
    end
  end

  config.model 'PrintType' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           310
    label            'Print Type'
    label_plural     'Print Types'

    list do
      sort_by :position
      field :name
      field :code
      field :position
    end

    show do
      field :id
      field :name
      field :code
      field :position
      field :created_at
      field :updated_at
    end

    edit do
      field :name do
        help 'Human‐readable label (e.g. “FDM”).'
      end
      field :code do
        help 'Machine value (e.g. “fdm”). Must be unique.'
      end
      field :position do
        help 'Order in dropdowns.'
      end
    end
  end

  config.model 'StaffUser' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           320
    label_plural     'Staff Users'

    list do
      field :id
      field :name
      field :email
      field :admin
    end

    edit do
      field(:name)  { read_only true }
      field(:email) { read_only true }
      field :admin
    end
  end

  config.model 'Patron' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           330
    label_plural     'Patrons'
    object_label_method :name

    # ─── SHOW ───────────────────────────────────────────────
    show do
      include_all_fields

      # Only admins see everything. Non-admins see just name, email, jobs:
      fields.each do |field|
        field.visible do
          bindings[:controller].current_staff_user.admin? ||
            [:name, :email, :jobs].include?(field.name)
        end
      end

      # Render the jobs association as links back to each job’s show
      field :jobs, :has_many_association do
        pretty_value do
          bindings[:object].jobs.map do |job|
            bindings[:view].link_to(
              "##{job.id} (#{job.type.demodulize})",
              bindings[:view].rails_admin.show_path(
                model_name: 'job',
                id:         job.id
              )
            )
          end.join(', ').html_safe
        end
      end
    end

    list do
      field :id
      field :email
      field :name
      field :jobs
    end
  end

  config.model 'Status' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           340
    label_plural     'Statuses'

    list do
      field :id
      field :name
      field :code
      field :position
      field :jobs_count do
        label       'Job Count'
        pretty_value { bindings[:object].jobs_count }
        sortable    false
        searchable  false
      end
    end

    edit do
      field :name
      field :code
      field :position
    end
  end

  config.model 'Category' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           350
    label            'Category'
    label_plural     'Categories'

    list do
      sort_by :position
      field :name
      field :position
    end

    edit do
      field :name
      field :position
    end
  end

  config.model 'Conversation' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           360
    label_plural     'Conversations'
  end

  config.model 'Message' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           370
    label_plural     'Messages'

    list do
      exclude_fields :images
    end
  end
end
