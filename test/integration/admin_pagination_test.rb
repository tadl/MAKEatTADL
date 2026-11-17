require "test_helper"

class AdminPaginationTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @staff = create_staff_user(email: "pagination@example.org", admin: true)
    @patron = create_patron(email: "avery@example.org", name: "Avery Example")
    attributes = { patron: @patron, category: Category.find_by!(name: "Patron"),
      status: Status.find_by!(code: "pending"), pickup_location: "wood", created_at: Time.zone.local(2026, 11, 16, 12) }
    @jobs = 103.times.map do |index|
      PrintJob.create!(attributes.merge(url: "https://example.org/pagination-sample/#{index}"))
    end
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: @staff.uid,
      info: { email: @staff.email, name: @staff.name },
      extra: { id_info: { hd: "example.org", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end

  test "default and selected page sizes have matching top and bottom controls" do
    [nil, 25, 50, 100].each do |size|
      get admin_jobs_path, params: { per_page: size }.compact
      assert_response :success
      per_page = size || 25
      assert_equal @jobs.reverse.first(per_page).map(&:id), displayed_job_ids
      assert_select 'nav[aria-label="Pagination top"]', count: 1
      assert_select 'nav[aria-label="Pagination bottom"]', count: 1
      assert_select 'nav select[name="per_page"]', count: 2 do |selects|
        selects.each do |select|
          assert_equal %w[25 50 100], select.css("option").map { |option| option["value"] }
          assert_equal per_page.to_s, select.at_css("option[selected]")["value"]
        end
      end
      assert_select 'nav [aria-current="page"][aria-disabled="true"]', text: "1", count: 2
      assert_select 'nav a[rel="prev"]', count: 0
    end
  end

  test "page navigation keeps filters and ordering with no overlap between pages" do
    filters = { per_page: 25, q: "pagination-sample", scope: "all", sort: "id", direction: "asc" }
    get admin_jobs_path, params: filters.merge(page: 1)
    first_page = displayed_job_ids

    get admin_jobs_path, params: filters.merge(page: 2)
    assert_response :success
    assert_equal @jobs.drop(25).first(25).map(&:id), displayed_job_ids
    assert_empty first_page & displayed_job_ids
    assert_select 'nav[aria-label="Pagination top"] a[rel="next"]' do |links|
      url = URI.parse(links.first["href"])
      assert_equal "/admin/jobs", url.path
      assert_nil url.host
      assert_equal filters.stringify_keys.transform_values(&:to_s).merge("page" => "3"), Rack::Utils.parse_nested_query(url.query)
    end
    assert_select 'nav[aria-label="Pagination top"] form' do |forms|
      fields = forms.first.css('input[type="hidden"]').to_h { |input| [input["name"], input["value"]] }
      assert_equal filters.except(:per_page).stringify_keys.transform_values(&:to_s), fields
      assert_nil fields["page"]
    end
  end

  test "invalid sizes and malformed or out of range pages stay bounded" do
    ["0", "-1", "999999", "50junk", ["100"], { value: "100" }].each do |size|
      get admin_jobs_path, params: { per_page: size }
      assert_response :success
      assert_equal 25, displayed_job_ids.size
    end
    ["junk", "0", "-5", ["2"], { value: "2" }].each do |page|
      get admin_jobs_path, params: { page: page }
      assert_response :success
      assert_equal @jobs.reverse.first(25).map(&:id), displayed_job_ids
    end
    get admin_jobs_path, params: { page: "9999999999999999999999999" }
    assert_response :success
    assert_equal @jobs.reverse.drop(100).map(&:id), displayed_job_ids
    assert_select 'nav [aria-current="page"]', text: "5", count: 2
    assert_select 'nav a[rel="next"]', count: 0
  end

  test "page size forms preserve nested queries and pagination links stay on this path" do
    get admin_jobs_path, params: { host: "external.example.org", protocol: "https", only_path: "false",
      per_page: 25, page: 2, filters: { codes: ["one", 'two"><script>synthetic</script>'] } }
    assert_response :success
    assert_select 'nav[aria-label^="Pagination"] a' do |links|
      links.each do |link|
        url = URI.parse(link["href"])
        assert_nil url.host
        assert_equal "/admin/jobs", url.path
        query = Rack::Utils.parse_nested_query(url.query)
        assert_equal ["one", 'two"><script>synthetic</script>'], query.dig("filters", "codes")
      end
    end
    assert_select 'nav[aria-label="Pagination top"] form' do |forms|
      assert_equal "/admin/jobs", forms.first["action"]
      assert_equal ["one", 'two"><script>synthetic</script>'], forms.first.css('input[name="filters[codes][]"]').map { |input| input["value"] }
    end
    assert_select "nav script", count: 0
  end

  test "small lists omit pagination while long patron history retains it" do
    [admin_patrons_path, admin_printable_models_path, admin_resources_path(resource: "statuses")].each do |path|
      get path, params: { per_page: 50 }
      assert_response :success
      assert_select 'nav[aria-label^="Pagination"]', count: 0
    end
    get admin_patron_path(@patron), params: { per_page: 50 }
    assert_response :success
    assert_select 'nav[aria-label="Pagination top"]', count: 1
    assert_select 'nav[aria-label="Pagination bottom"]', count: 1
    assert_select 'nav select[name="per_page"] option[value="50"][selected]', count: 2
  end

  test "pagination begins above 25 results and omits page buttons when a larger size fits" do
    status = Status.find_by!(code: "approved")
    Job.where(id: @jobs.first(25).map(&:id)).update_all(status_id: status.id)

    get admin_jobs_path, params: { status_id: status.id }
    assert_response :success
    assert_select 'nav[aria-label^="Pagination"]', count: 0

    @jobs[25].update!(status: status)
    get admin_jobs_path, params: { status_id: status.id }
    assert_response :success
    assert_select 'nav a[rel="next"]', count: 2

    get admin_jobs_path, params: { status_id: status.id, per_page: 50 }
    assert_response :success
    assert_equal 26, displayed_job_ids.size
    assert_select 'nav select[name="per_page"] option[value="50"][selected]', count: 2
    assert_select 'nav[aria-label^="Pagination"] a', count: 0
    assert_select 'nav[aria-label^="Pagination"] [aria-disabled]', count: 0
  end

  private

  def displayed_job_ids
    css_select('tr[data-controller="row-link"] th[scope="row"] a').map { |link| link.text.delete_prefix("#").to_i }
  end
end
