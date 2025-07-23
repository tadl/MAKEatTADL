Rails.application.routes.draw do
  # OmniAuth callback for external providers (login)
  match '/auth/:provider/callback', to: 'sessions#create', via: [:get, :post]

  # Sign out route
  delete '/logout', to: 'sessions#destroy', as: :logout

  # Admin interface (RailsAdmin)
  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'
  # RailsAdmin conversation action for Job (formerly PrintJob)
  match '/admin/job/:id/conversation',
        to: 'rails_admin/main#conversation',
        via: [:get, :post],
        as: :admin_job_conversation

  # Public home page
  root to: 'portal#home'

  # 3D print & scan request submission
  # “Regular” 3D prints (patron‐type)
  scope defaults: { type: 'patron' } do
    get  '/submit-print', to: 'portal#submit_print',   as: :submit_print
    post '/submit-print', to: 'portal#create_print_job', as: :create_print_job
  end

  # “Fidget” prints (fidget‐type)
  scope defaults: { type: 'fidget' } do
    get  '/submit-fidget', to: 'portal#submit_print',   as: :submit_fidget
    post '/submit-fidget', to: 'portal#create_print_job', as: :create_fidget_job
  end

  # "Assistive" prints (assistive-type)
  scope defaults: { type: 'assistive' } do
    get '/submit-assistive', to: 'portal#submit_print', as: :submit_assistive
    post '/submit-assistive', to: 'portal#create_print_job', as: :create_assistive_job
  end

  # "Staff" print requests
  scope defaults: { type: 'staff' } do
    get  '/submit-staff', to: 'portal#submit_print',   as: :submit_staff
    post '/submit-staff', to: 'portal#create_print_job', as: :create_staff_job
  end

  get  '/submit-scan',    to: 'portal#submit_scan',       as: :submit_scan
  post '/submit-scan',    to: 'portal#create_scan_job',   as: :create_scan_job

  get '/thank-you',      to: 'portal#thank_you',        as: :thank_you

  # Magic-link login (token request)
  get  '/login',           to: 'portal#token_request',   as: :login
  post '/login',           to: 'portal#send_token',       as: :send_login
  get  '/token_thank_you', to: 'portal#token_thank_you', as: :token_thank_you

  # Patron dashboard & job details (requires token in params or cookie)
  get  '/dashboard',                to: 'portal#dashboard',      as: :dashboard
  get  '/jobs/:id',                 to: 'portal#show',           as: :job
  post '/jobs/:id/conversation',    to: 'portal#create_message', as: :job_conversation

  get "/reports/print", to: "reports#print", as: :print_report

  # Health check endpoint
  get '/up', to: 'rails/health#show', as: :rails_health_check

  # Inbound mailgun webhooks
  post  '/inbound/mailgun', to: 'inbound#mailgun'
end

