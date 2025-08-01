class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user.is_a?(StaffUser)

    # Always allow staff to enter RailsAdmin
    can :access, :rails_admin
    can :read,   :dashboard

    if user.admin?
      can :manage, :all
    else
      # Jobs: view & update only (index, show, edit, update)
      alias_action :index, :show, :edit, :update, to: :read
      can   :read,   Job
      can   :update, Job
      can   :conversation, Job
      can   :files, Job
      can   :help, Job

      # Lookup tables: only read, block all modification
      lookups = [
        Status,
        Category,
        Printer,
        PrintType,
        FilamentColor,
        PickupLocation,
        Patron,
        PrintableModel
      ]

      can    :read, lookups

      cannot :edit,    lookups
      cannot :update,  lookups
      cannot :destroy, lookups
      cannot :create,  lookups

      # Patron: allow update (edit name/email), but not create/destroy
      can    :update, Patron
      cannot :destroy, Patron
      cannot :create,  Patron

      # Jobs: disallow destructive actions
      cannot :destroy, Job

      # Disallow manage for these models
      cannot :manage, [
        Message,
        Conversation,
        StaffUser
      ]
    end
  end
end
