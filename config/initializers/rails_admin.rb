# config/initializers/rails_admin.rb
require Rails.root.join('lib/rails_admin/config/actions/conversation')
require Rails.root.join('lib', 'rails_admin', 'config', 'actions', 'help')
require Rails.root.join('lib/rails_admin/config/actions/files')

# Global alphabetical ordering helper for association dropdowns (never use :position)
ALPHA_ORDER = ->(scope) do
  cols = scope.klass.column_names
  if cols.include?('name')
    scope.reorder(nil).order(Arel.sql('LOWER(name) ASC'))
  elsif cols.include?('title')
    scope.reorder(nil).order(Arel.sql('LOWER(title) ASC'))
  elsif cols.include?('email')
    scope.reorder(nil).order(Arel.sql('LOWER(email) ASC'))
  else
    scope.reorder(nil).order(:id)
  end
end

# Safe global default for ALL RailsAdmin association pickers (doesn't enumerate models at boot)
RailsAdmin::Config::Fields::Association.register_instance_option :associated_collection_scope do
  ALPHA_ORDER
end

RailsAdmin.config do |config|
  config.authorize_with :cancancan, Ability

  # Authentication & inheritance
  config.parent_controller = '::ApplicationController'
  config.authenticate_with do
    redirect_to '/admin/login' unless current_staff_user
  end
  config.current_user_method(&:current_staff_user)

  config.asset_source           = :sprockets
  config.default_items_per_page = 10

  # App name & included models
  config.main_app_name   = ['MAKE@TADL', '  Job Management System']
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

  # Actions
  config.actions do
    dashboard
    index
    new   { except ['StaffUser'] }
    export
    bulk_delete do
      visible { bindings[:controller].current_staff_user.admin? }
    end
    show
    edit do
      visible do
        bindings[:controller].current_ability.can?(:update, bindings[:abstract_model].model)
      end
    end
    conversation { only ['Job'] }
    files        { only ['Job'] }
    delete do
      visible do
        bindings[:controller].current_ability.can?(:destroy, bindings[:abstract_model].model)
      end
    end
    help
  end

  # -----------------------------
  # Management (Jobs and Patrons)
  # -----------------------------
  config.model 'Job' do
    navigation_label 'Management'
    weight           100
    label_plural     'Jobs'

    list do
      scopes  [:active, :inactive, :ongoing]
      sort_by :created_at
      field(:id) { label 'Job' }
      field :patron
      field :status, :belongs_to_association do
        label        'Status'
        pretty_value { bindings[:object].status.name }
        filterable   true
        filter_options { Status.order(:name).pluck(:name, :id) }
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
      field :pickup_location do
        label 'Pickup Location'
        pretty_value do
          if value.present?
            PickupLocation.find_by(code: value)&.name || value.humanize
          else
            ''
          end
        end
      end
      field :created_at do
        label 'Received'
        pretty_value { value&.in_time_zone('America/Detroit')&.strftime('%b %-d, %Y %-l:%M%P') }
      end
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
      field(:type) { label 'Job Type' }
      field :notes
      field :model_files, :active_storage do
        label 'Model Files'
        pretty_value do
          value.map.with_index do |file, i|
            file_url = Rails.application.routes.url_helpers.rails_blob_url(file, only_path: true)
            html_id  = "stlviewer-#{i}"

            if File.extname(file.filename.to_s).downcase == '.stl'
              %Q{
                <div>
                  <details id="stl-details-#{i}">
                    <summary class="btn btn-sm btn-primary ">Show 3D Preview</summary>
                    <div id="#{html_id}" class="stlviewer" data-file-url="#{file_url}" style="width: 400px; height: 300px; border:1px solid #ccc"></div>
                  </details>
                  <div class="py-2"><a href="#{file_url}">#{file.filename}</a></div>
                </div>
              }.html_safe
            else
              %Q{<div><a href="#{file_url}">#{file.filename}</a></div>}
            end
          end.join.html_safe
        end
      end

      group :print_fields do
        label   'Print Details'
        visible { bindings[:object].is_a?(PrintJob) }
        field :print_type, :belongs_to_association do
          label          'Print Type'
          pretty_value   { bindings[:object].print_type&.name }
          filterable     true
          associated_collection_scope { ALPHA_ORDER }
        end
        field :url do
          label 'URL'
          pretty_value do
            if value.present?
              bindings[:view].link_to(value, value, target: '_blank', rel: 'noopener')
            else
              bindings[:view].content_tag(:span, '(none)', class: 'text-muted')
            end
          end
        end
        field :filament_color
        field(:print_time_estimate_hm) { label 'Print time estimate' }
        field :slicer_weight
        field :slicer_cost do
          label 'Estimated cost'
          formatted_value { value.present? ? bindings[:view].number_to_currency(value) : '' }
          pretty_value    { value.present? ? bindings[:view].number_to_currency(value) : '' }
        end
        field :actual_weight
        field(:resin_volume_ml) { label 'Resin Volume (mL)' }
        field :actual_cost
        field :completion_date
        field :pickup_date
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
                img.variant(resize_to_limit: [300, 300]),
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
        read_only true
        associated_collection_scope { ALPHA_ORDER }
        inline_add   { bindings[:controller].current_staff_user.admin? }
        inline_edit  { bindings[:controller].current_staff_user.admin? }
        help ''
      end
      field :status, :belongs_to_association do
        label 'Status'
        associated_collection_scope { ALPHA_ORDER }
        inline_add   { bindings[:controller].current_staff_user.admin? }
        inline_edit  { bindings[:controller].current_staff_user.admin? }
        help ''
      end
      field :category, :belongs_to_association do
        label 'Category'
        associated_collection_scope { ALPHA_ORDER }
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
        enum { PickupLocation.where(active: true).order(Arel.sql('LOWER(name) ASC')).pluck(:name, :code) }
        help ''
      end
      field :notes do
        help 'Notes from requestor. Print jobs for Asssitive/Fidget categories will include relevant contact method/info and/or company/organization information here.'
      end
      field(:model_files) { visible false }

      group :print_fields do
        label   'Print-only fields'
        visible { bindings[:object].is_a?(PrintJob) }
        field :assigned_printer, :belongs_to_association do
          inline_add   { bindings[:controller].current_staff_user.admin? }
          inline_edit  { bindings[:controller].current_staff_user.admin? }
          associated_collection_scope { ALPHA_ORDER }
          help 'The printer that will be used for this job.'
        end
        field :print_type, :belongs_to_association do
          inline_add   { bindings[:controller].current_staff_user.admin? }
          inline_edit  { bindings[:controller].current_staff_user.admin? }
          label        'Print Type'
          associated_collection_scope { ALPHA_ORDER }
          help 'Automatically set from the assigned printer.'
        end
        field :url do
          label 'URL'
          help 'A URL is provided by the requestor when a model file is not.'
          partial 'url_with_open'
        end
        field :filament_color, :enum do
          enum do
            FilamentColor.where(active: true)
                         .pluck(:name, :code)                 # [["Black","black"], ...]
                         .sort_by { |(name, _)| name.to_s.downcase }
          end
          default_value { bindings[:object].filament_color }
          help ''
        end
        field(:quantity, :integer) { label 'Quantity'; help 'Number of copies printed. Update this when printing additional copies.' }
        field :print_notify, :boolean do
          label 'Notify patron when printing starts (public printers only)'
          help  'Sends an email and portal message on transition to In Progress.'
        end
        field(:print_time_estimate_hm) { label 'Print time estimate'; help 'Enter estimated print duration from slicer. Format: HH:MM.' }
        field(:slicer_weight)          { label 'Weight estimate (grams)'; help 'Estimated weight from slicer.' }
        field :slicer_cost do
          label 'Estimated cost'
          read_only true
          help 'Auto-calculated from weight estimate.'
          formatted_value { value.present? ? bindings[:view].number_to_currency(value) : '' }
          pretty_value    { value.present? ? bindings[:view].number_to_currency(value) : '' }
        end
        field(:resin_volume_ml) { label 'Resin Volume (mL)'; help 'How many milliliters of resin were used?' }
        field(:actual_weight)   { label 'Weight (grams)';    help 'Enter when the print is finished — this auto-sets Actual cost, marks Ready for pickup, and emails the patron.' }
        field :actual_cost do
          read_only true
          help 'Auto calculated from actual weight.'
          formatted_value { value.present? ? bindings[:view].number_to_currency(value) : '' }
          pretty_value    { value.present? ? bindings[:view].number_to_currency(value) : '' }
        end
        field(:completion_date, :date) { help "Set this to today's date when the print is completed." }
        field(:pickup_date, :date)     { help "Set this to today's date when the print is picked up." }
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

  config.model 'Patron' do
    navigation_label 'Management'
    weight           110
    label_plural     'Patrons'
    object_label_method :name

    list do
      field :id
      field :email
      field :name
      field :jobs
    end

    show do
      fields :id, :email, :name
      field :jobs, :has_many_association do
        pretty_value do
          bindings[:object].jobs.map do |job|
            bindings[:view].link_to(
              "##{job.id} (#{job.type.demodulize})",
              bindings[:view].rails_admin.show_path(model_name: 'job', id: job.id)
            )
          end.join(', ').html_safe
        end
        visible { true }
      end
      fields :access_token, :token_sent_at, :audits do
        visible { bindings[:controller].current_staff_user.admin? }
      end
    end

    edit do
      field :name
      field :email
      fields :access_token, :token_sent_at, :jobs, :audits do
        visible { bindings[:controller].current_staff_user.admin? }
      end
    end
  end

  # ----------------
  # Form Options etc
  # ----------------
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
      field :rgb do
        pretty_value do
          if value.present?
            %(<span style="display:inline-block;width:14px;height:14px;vertical-align:middle;border:1px solid #ccc;background:#{value};margin-right:6px;"></span> #{value}).html_safe
          else
            ''
          end
        end
      end
    end

    edit do
      field :name
      field :code
      field :active
      field :rgb do
        label 'Hex Color'
        help  'Optional: e.g. #ff9900 (used in dashboard pie chart)'
      end
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
      field :category do
        associated_collection_scope { ALPHA_ORDER }
      end
      field :notes
      field :model_file, :active_storage do
        label 'Model File (STL)'
        help  'Attach the .stl file for this model'
        pretty_value do
          if value&.attached?
            file_url = Rails.application.routes.url_helpers.rails_blob_url(value, only_path: true)
            %Q{<div class="mb-2">Currently attached: <a href="#{file_url}">#{value.filename}</a></div>}.html_safe
          else
            '<span class="text-muted">(No file attached)</span>'.html_safe
          end
        end
      end
      field :preview_image , :active_storage do
        label 'Photo'
        help  'Attach a PNG/JPG preview for this model'
      end
    end

    show do
      field :name
      field :code
      field :category
      field :notes
      field :model_file, :active_storage do
        label 'Model File (STL)'
        pretty_value do
          if value.present?
            file = value
            file_url = Rails.application.routes.url_helpers.rails_blob_url(file, only_path: true)
            html_id  = "stlviewer-#{file.id}"

            if File.extname(file.filename.to_s).downcase == '.stl'
              %Q{
                <div>
                  <details id="stl-details-#{file.id}">
                    <summary class="btn btn-sm btn-primary">Show 3D Preview</summary>
                    <div id="#{html_id}" class="stlviewer" data-file-url="#{file_url}" style="width: 400px; height: 300px; border:1px solid #ccc"></div>
                  </details>
                  <div class="py-2"><a href="#{file_url}">#{file.filename}</a></div>
                </div>
              }.html_safe
            else
              %Q{<div><a href="#{file_url}">#{file.filename}</a></div>}.html_safe
            end
          else
            '(none)'
          end
        end
      end
      field :preview_image
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
      field(:scanner, :boolean)     { help 'Check if this location has a 3D scanner' }
      field(:fdm_printer, :boolean) { help 'Check if this location has an FDM printer' }
      field(:resin_printer, :boolean) { help 'Check if this location has a resin printer' }
      field :printers, :has_many_association do
        label 'Printers at this Location'
        help  'Select which printers live at this pickup location'
        inline_add  { bindings[:controller].current_staff_user.admin? }
        inline_edit { bindings[:controller].current_staff_user.admin? }
        associated_collection_scope { ALPHA_ORDER }
      end
    end
  end

  # -----------
  # Admin area
  # -----------
  config.model 'Audited::Audit' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           299
    label_plural     'Activity Log'
    list do
      field :created_at
      field :user
      field :auditable
      field :action
      field :audited_changes
    end
    show { include_all_fields }
  end

  config.model 'Printer' do
    visible { bindings[:controller].current_staff_user.admin? }
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
        associated_collection_scope { ALPHA_ORDER }
      end
      field :print_type, :belongs_to_association do
        label           'Print Type'
        inline_add      true
        inline_edit     true
        associated_collection_scope { ALPHA_ORDER }
      end
      field :printer_model
      field(:bed_size, :string) { help 'e.g. 200x200x200 mm' }
      field :location
      field :public, :boolean do
        label 'Publicly viewable'
        help  'Only public printers trigger patron “in progress” notifications.'
      end
    end
  end

  config.model 'PrintType' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           310
    label            'Print Type'
    label_plural     'Print Types'

    list do
      sort_by :name
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
      field(:name)     { help 'Human‐readable label (e.g. “FDM”).' }
      field(:code)     { help 'Machine value (e.g. “fdm”). Must be unique.' }
      field(:position) { help 'Legacy field (not used for ordering).' }
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

  config.model 'Status' do
    visible          { bindings[:controller].current_staff_user.admin? }
    navigation_label 'Admin'
    weight           340
    label_plural     'Statuses'

    list do
      sort_by :name
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
      sort_by :name
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
    list { exclude_fields :images }
  end
end
