require "test_helper"

class ScanJobTest < ActiveSupport::TestCase
  { "stl" => "model/stl", "3mf" => "application/zip" }.each do |extension, content_type|
    test "attaching a #{extension} model preserves the scan job through subsequent updates" do
      job = create_scan_job
      original_status_id = job.status_id

      job.model_files.attach(
        io: file_fixture("test-model.#{extension}").open,
        filename: "test-model.#{extension}",
        content_type: content_type
      )

      assert_instance_of ScanJob, job.reload
      assert_equal "ScanJob", Job.find(job.id).type
      assert_equal "scan", job.origin
      assert_equal original_status_id, job.status_id
      assert_equal 1, job.model_files.count

      job.update!(notes: "Scan delivered digitally; no print requested.")
      assert_equal "ScanJob", job.reload.type
      assert_equal 1, job.model_files.count
    end
  end
end
