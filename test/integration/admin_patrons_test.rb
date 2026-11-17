require "test_helper"
require "csv"

class AdminPatronsTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff_user
    sign_in_staff(@staff)
  end

  test "staff can search patrons and view paginated job history" do
    patron = create_patron(name: "Library Sample", email: "library-sample@example.org")
    other_patron = create_patron(name: "Another Patron")
    job = create_print_job(patron: patron)

    get admin_patrons_path(q: "library-sample")

    assert_response :success
    assert_select "a[href='#{admin_patron_path(patron)}']", minimum: 1
    assert_select "a[href='#{admin_patron_path(other_patron)}']", count: 0
    assert_select "a[href='#{new_admin_patron_path}']", count: 0

    get admin_patron_path(patron)

    assert_response :success
    assert_select "a[href='#{admin_job_path(job)}']", text: "##{job.id}"
    assert_not_includes response.body, patron.access_token
    assert_select "a[href='#{merge_admin_patron_path(patron)}']", count: 0
  end

  test "staff can change contact details without changing tokens or job ownership" do
    patron = create_patron
    other_patron = create_patron
    job = create_print_job(patron: other_patron)
    token = patron.access_token
    timestamp = patron.token_sent_at

    patch admin_patron_path(patron), params: { patron: {
      name: "Updated Name", email: " UPDATED@example.org ",
      access_token: "replacement-token", token_sent_at: 20.years.from_now,
      job_ids: [job.id], admin: true
    } }

    assert_redirected_to admin_patron_path(patron)
    patron.reload
    assert_equal "Updated Name", patron.name
    assert_equal "updated@example.org", patron.email
    assert_equal token, patron.access_token
    assert_equal timestamp, patron.token_sent_at
    assert_equal other_patron.id, job.reload.patron_id
  end

  test "invalid contact details render useful errors" do
    patron = create_patron

    patch admin_patron_path(patron), params: { patron: { email: "invalid" } }

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /Email must look like/
    assert_not_equal "invalid", patron.reload.email
  end

  test "malformed patron parameter roots return bad request" do
    @staff.update!(admin: true)
    patron = create_patron

    assert_no_difference "Patron.count" do
      post admin_patrons_path, params: { patron: "invalid" }
    end
    assert_response :bad_request

    patch admin_patron_path(patron), params: { patron: ["invalid"] }
    assert_response :bad_request
    assert_equal "Test Patron", patron.reload.name
  end

  test "search treats SQL wildcard characters literally" do
    matching = create_patron(name: "Sample_100%")
    other = create_patron(name: "SampleA100B")

    get admin_patrons_path(q: "Sample_100%")

    assert_response :success
    assert_select "a[href='#{admin_patron_path(matching)}']", minimum: 1
    assert_select "a[href='#{admin_patron_path(other)}']", count: 0
  end

  test "patron pagination is bounded and preserves the search" do
    26.times { |index| create_patron(name: "Paged Patron #{index}") }

    get admin_patrons_path(q: "Paged Patron", page: 2)

    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "nav[aria-label^='Pagination'] a[rel='prev']", text: "< Prev", count: 2
    assert_select "nav[aria-label^='Pagination'] [aria-current='page']", text: "2", count: 2
    assert_select "nav[aria-label='Pagination top'] a[rel='prev']" do |links|
      assert_equal "Paged Patron", Rack::Utils.parse_nested_query(URI.parse(links.first["href"]).query)["q"]
    end
  end

  test "admin can create and delete a patron" do
    @staff.update!(admin: true)

    assert_difference "Patron.count", 1 do
      post admin_patrons_path, params: { patron: { name: "Created Patron", email: "created@example.org" } }
    end
    patron = Patron.find_by!(email: "created@example.org")
    assert_redirected_to admin_patron_path(patron)

    assert_difference "Patron.count", -1 do
      delete admin_patron_path(patron)
    end
    assert_redirected_to admin_patrons_path
  end

  test "admin bulk delete acts only on selected patrons" do
    @staff.update!(admin: true)
    selected = create_patron
    retained = create_patron

    post bulk_destroy_admin_patrons_path, params: { ids: [selected.id] }

    assert_redirected_to admin_patrons_path
    assert_not Patron.exists?(selected.id)
    assert Patron.exists?(retained.id)
  end

  test "admin merge moves jobs and patron messages to the selected record" do
    @staff.update!(admin: true)
    loser = create_patron(name: "Duplicate Patron")
    winner = create_patron(name: "Keep Patron")
    job = create_print_job(patron: loser)
    message = job.conversation.messages.create!(author: loser, body: "Synthetic patron reply")

    get merge_admin_patron_path(loser)
    assert_response :success
    assert_select "select[name='target_patron_id'] option[value='#{loser.id}']", count: 0

    post merge_admin_patron_path(loser), params: { target_patron_id: winner.id }

    assert_redirected_to admin_patron_path(winner)
    assert_equal winner.id, job.reload.patron_id
    assert_equal winner.id, message.reload.author_id
    assert_not Patron.exists?(loser.id)
  end

  test "invalid merge target does not change patrons or jobs" do
    @staff.update!(admin: true)
    patron = create_patron
    job = create_print_job(patron: patron)

    post merge_admin_patron_path(patron), params: { target_patron_id: patron.id }

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /Choose two different patrons/
    assert_equal patron.id, job.reload.patron_id
    assert Patron.exists?(patron.id)
  end

  test "admin exports allowlisted fields and protects CSV formulas" do
    @staff.update!(admin: true)
    patron = create_patron(name: "=1+1", email: "export-sample@example.org")

    get export_admin_patrons_path(format: :csv, q: patron.email)

    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal ["ID", "Name", "Email", "Created"], rows.headers
    assert_equal "'=1+1", rows.first["Name"]
    assert_not_includes response.body, patron.access_token

    get export_admin_patrons_path(format: :json, q: patron.email)

    assert_response :success
    records = JSON.parse(response.body)
    assert_equal %w[created_at email id name], records.first.keys.sort
    assert_equal patron.id, records.first["id"]

    get export_admin_patrons_path(format: :xml, q: patron.email)

    assert_response :success
    xml = Nokogiri::XML(response.body)
    assert_equal "=1+1", xml.at_xpath("/patrons/patron/name").text
    assert_not_includes response.body, patron.access_token
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: "https://example.org/avatar.png" },
      extra: { id_info: { hd: "example.org", email_verified: true } }
    )
    with_env("GOOGLE_DOMAIN" => "example.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
