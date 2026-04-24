require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "setting pickup_date archives the job" do
    job = create_print_job(status_code: "ready_for_pickup")
    archived = Status.find_by!(code: "archived")

    job.update!(pickup_date: Date.current)

    assert_equal archived.id, job.reload.status_id
  end

  test "transition to in progress records the starting staff user and timestamp" do
    job = create_print_job(status_code: "approved")
    staff = create_staff_user(email: "starter@tadl.org")

    Current.staff_user = staff
    job.update!(status: Status.find_by!(code: "in_progress"))

    job.reload
    assert_equal staff.id, job.started_by_id
    assert_not_nil job.started_at
  ensure
    Current.staff_user = nil
  end

  test "transition to ready for pickup records the finishing staff user and timestamp" do
    job = create_print_job(status_code: "in_progress")
    staff = create_staff_user(email: "finisher@tadl.org")

    Current.staff_user = staff
    job.update!(status: Status.find_by!(code: "ready_for_pickup"))

    job.reload
    assert_equal staff.id, job.finished_by_id
    assert_not_nil job.finished_at
  ensure
    Current.staff_user = nil
  end

  test "setting actual weight records completion staff and timestamp" do
    job = create_print_job(status_code: "in_progress")
    staff = create_staff_user(email: "actual-finisher@tadl.org")

    Current.staff_user = staff
    job.update!(actual_weight: 12.5)

    job.reload
    assert_equal Status.find_by!(code: "ready_for_pickup").id, job.status_id
    assert_equal staff.id, job.finished_by_id
    assert_not_nil job.finished_at
  ensure
    Current.staff_user = nil
  end

  test "setting resin volume records completion staff and timestamp" do
    job = create_print_job(
      status_code: "in_progress",
      attrs: { print_type: ensure_print_type("resin", name: "Resin") }
    )
    staff = create_staff_user(email: "resin-finisher@tadl.org")

    Current.staff_user = staff
    job.update!(resin_volume_ml: 8.5)

    job.reload
    assert_equal Status.find_by!(code: "ready_for_pickup").id, job.status_id
    assert_equal staff.id, job.finished_by_id
    assert_not_nil job.finished_at
  ensure
    Current.staff_user = nil
  end

  test "rejects zip typed stl uploads" do
    job = create_print_job

    job.model_files.attach(
      io: file_fixture("test-model.stl").open,
      filename: "test-model.stl",
      content_type: "application/zip"
    )

    assert_not job.valid?
    assert_includes job.errors[:model_files].first, "must be STL (.stl) or 3MF (.3mf)"
  end

  test "accepts zip typed 3mf uploads" do
    job = create_print_job

    job.model_files.attach(
      io: file_fixture("test-model.3mf").open,
      filename: "test-model.3mf",
      content_type: "application/zip"
    )

    assert job.valid?
  end
end
