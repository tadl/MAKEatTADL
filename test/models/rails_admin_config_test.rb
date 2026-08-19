require "test_helper"

class RailsAdminConfigTest < ActiveSupport::TestCase
  test "stats is a root navigation action authorized like the dashboard" do
    action = RailsAdmin::Config::Actions.all.detect { |candidate| candidate.action_name == :stats }

    assert_not_nil action
    assert action.root?
    assert action.show_in_navigation
    assert_equal :dashboard, action.authorization_key
  end

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

  test "merge patron action is only visible to admins on patrons" do
    patron = create_patron
    controller_class = Struct.new(:current_staff_user, :current_ability)
    admin_user = create_staff_user(admin: true)
    non_admin_user = create_staff_user(admin: false)
    admin_controller = controller_class.new(admin_user, Ability.new(admin_user))
    non_admin_controller = controller_class.new(non_admin_user, Ability.new(non_admin_user))
    registered_action = RailsAdmin::Config::Actions.all.detect { |action| action.action_name == :merge_patron }

    admin_action = registered_action.dup
    admin_action.bindings = { controller: admin_controller, object: patron, abstract_model: RailsAdmin::AbstractModel.new(Patron) }

    non_admin_action = registered_action.dup
    non_admin_action.bindings = { controller: non_admin_controller, object: patron, abstract_model: RailsAdmin::AbstractModel.new(Patron) }

    assert_not_nil registered_action
    assert admin_action.send(:visible?)
    assert_not non_admin_action.send(:visible?)
  end
end
