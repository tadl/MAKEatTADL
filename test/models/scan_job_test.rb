require "test_helper"

class ScanJobTest < ActiveSupport::TestCase
  test "attaching a 3mf model converts the scan job into a print job" do
    job = create_scan_job

    job.model_files.attach(
      io: file_fixture("test-model.3mf").open,
      filename: "test-model.3mf",
      content_type: "application/zip"
    )
    job.touch
    job = Job.find(job.id)

    assert_equal "PrintJob", job.type
  end
end
