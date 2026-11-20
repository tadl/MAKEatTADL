class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user.is_a?(StaffUser)

    can :access, :admin
    can :read, :dashboard

    if user.admin?
      can :manage, :all
    else
      can [:read, :update, :conversation, :files, :help, :picked_up], Job
      can [:read, :update], Patron

      # Lookup tables: only read, block all modification
      lookups = [
        Status,
        Category,
        Printer,
        PrintType,
        FilamentColor,
        PickupLocation,
        PrintableModel
      ]

      can :read, lookups
    end
  end
end
