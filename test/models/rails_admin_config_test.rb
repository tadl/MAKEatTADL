require "test_helper"

class RailsAdminConfigTest < ActiveSupport::TestCase
  test "job type field is read only in rails admin" do
    field = RailsAdmin.config("Job").edit.fields.detect { |configured_field| configured_field.name == :type }

    assert field.read_only?
    assert_match(/convert automatically/i, field.help)
  end

  test "rails admin disables direct new actions for conversations and messages" do
    conversation_action = RailsAdmin::Config::Actions.find(:new, abstract_model: RailsAdmin::AbstractModel.new("Conversation"))
    message_action = RailsAdmin::Config::Actions.find(:new, abstract_model: RailsAdmin::AbstractModel.new("Message"))
    job_action = RailsAdmin::Config::Actions.find(:new, abstract_model: RailsAdmin::AbstractModel.new("Job"))

    assert_not conversation_action.authorized?
    assert_not message_action.authorized?
    assert job_action.authorized?
  end

  test "picked up action is only visible for ready jobs" do
    ready_job = create_print_job(status_code: "ready_for_pickup")
    pending_job = create_print_job(status_code: "pending")
    abstract_model = RailsAdmin::AbstractModel.new(Job)

    ready_action = RailsAdmin::Config::Actions.find(:picked_up, abstract_model: abstract_model, object: ready_job)
    pending_action = RailsAdmin::Config::Actions.find(:picked_up, abstract_model: abstract_model, object: pending_job)

    assert ready_action.send(:visible?)
    assert_not pending_action.send(:visible?)
  end
end
