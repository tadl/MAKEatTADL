require "test_helper"

class AbilityTest < ActiveSupport::TestCase
  test "anonymous users have no staff permissions" do
    ability = Ability.new(nil)

    assert_not ability.can?(:access, :admin)
    assert_not ability.can?(:read, :dashboard)
    [Job, Patron, StaffUser, PrintableModel].each do |model|
      assert_not ability.can?(:read, model)
      assert_not ability.can?(:manage, model)
    end
  end

  test "staff can work existing jobs and patron contact details" do
    ability = Ability.new(StaffUser.new(admin: false))

    assert ability.can?(:access, :admin)
    assert ability.can?(:read, :dashboard)
    [Job, PrintJob, ScanJob, Patron].each do |model|
      %i[index show read edit update].each do |action|
        assert ability.can?(action, model), "staff should have #{action} on #{model}"
      end
    end
    %i[conversation files help].each { |action| assert ability.can?(action, Job) }
  end

  test "staff can read lookup records without changing them" do
    ability = Ability.new(StaffUser.new(admin: false))

    [Status, Category, Printer, PrintType, FilamentColor, PickupLocation, PrintableModel].each do |model|
      %i[index show read].each { |action| assert ability.can?(action, model) }
      %i[new create edit update destroy export].each do |action|
        assert_not ability.can?(action, model), "staff should not have #{action} on #{model}"
      end
    end
  end

  test "staff cannot create delete export merge or mark picked up" do
    ability = Ability.new(StaffUser.new(admin: false))

    [Job, Patron].each do |model|
      %i[new create destroy export bulk_delete].each { |action| assert_not ability.can?(action, model) }
    end
    assert_not ability.can?(:merge_patron, Patron)
    assert_not ability.can?(:picked_up, Job)
    [Message, Conversation, StaffUser, Audited::Audit].each do |model|
      %i[read create update destroy].each { |action| assert_not ability.can?(action, model) }
    end
  end

  test "administrators retain management permissions" do
    ability = Ability.new(StaffUser.new(admin: true))

    assert ability.can?(:access, :admin)
    [Job, Patron, StaffUser, Status, PrintableModel, Message, Conversation, Audited::Audit].each do |model|
      assert ability.can?(:manage, model)
      %i[read create update destroy export].each { |action| assert ability.can?(action, model) }
    end
    assert ability.can?(:picked_up, Job)
    assert ability.can?(:merge_patron, Patron)
  end
end
