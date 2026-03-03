require "test_helper"

class JobMailerTest < ActiveSupport::TestCase
  test "job_received falls back to a local sender when mailgun is not configured" do
    job = create_print_job

    with_env("MAILGUN_DOMAIN" => nil) do
      mail = JobMailer.job_received(job)

      assert_equal ["no-reply@localhost"], mail.from
      assert_equal ["no-reply@localhost"], mail.reply_to
    end
  end
end
