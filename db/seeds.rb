# Seeds should create only application-required reference data.
#
# Operational inventory such as pickup locations, printers, and the full filament
# catalog is managed through RailsAdmin so production choices are not recreated
# or overwritten by a later manual db:seed run.

def create_once!(model, finder, attrs)
  model.find_or_create_by!(finder) do |record|
    record.assign_attributes(attrs)
  end
end

###############################################################################
# 1) Filament Colors
###############################################################################

[
  { name: "White", code: "white", position: 1, active: true, rgb: "#ffffff" },
  { name: "Black", code: "black", position: 2, active: true, rgb: "#000000" }
].each do |attrs|
  create_once!(FilamentColor, { code: attrs[:code] }, attrs.except(:code))
end

###############################################################################
# 2) Print Types
###############################################################################

[
  { name: "FDM", code: "fdm", position: 1 },
  { name: "Resin", code: "resin", position: 2 }
].each do |attrs|
  create_once!(PrintType, { code: attrs[:code] }, attrs.except(:code))
end

###############################################################################
# 3) Statuses
###############################################################################

[
  { name: "Pending", code: "pending", position: 0 },
  { name: "Information Requested", code: "information_requested", position: 1 },
  { name: "Response Received", code: "response_received", position: 2 },
  { name: "Approved", code: "approved", position: 3 },
  { name: "In Progress", code: "in_progress", position: 4 },
  { name: "Ready for pickup", code: "ready_for_pickup", position: 5 },
  { name: "Archived", code: "archived", position: 6 },
  { name: "Ongoing", code: "ongoing", position: 7 },
  { name: "Cancelled", code: "cancelled", position: 8 },
  { name: "Rejected", code: "rejected", position: 9 },
  { name: "Abandoned", code: "abandoned", position: 10 }
].each do |attrs|
  create_once!(Status, { code: attrs[:code] }, attrs.except(:code))
end

###############################################################################
# 4) Categories
###############################################################################

[
  { name: "Patron", position: 1 },
  { name: "Staff", position: 2 },
  { name: "Assistive", position: 3 },
  { name: "Fidget", position: 4 }
].each do |attrs|
  create_once!(Category, { name: attrs[:name] }, attrs.except(:name))
end

###############################################################################
# 5) Printable Models
###############################################################################

[
  { name: "Calming Comb", code: "calming_comb", position: 0, notes: nil, category_name: "Fidget" },
  { name: "Concentric Flower", code: "concentric_flower", position: 1, notes: nil, category_name: "Fidget" },
  { name: "Fidget Spinner", code: "fidget_spinner", position: 2, notes: nil, category_name: "Fidget" },
  { name: "Key Turner", code: "key_turner", position: 3, notes: "The key turner allows people with arthritis or other disabilities to grasp their keys better. The key turner fits most standard size keys. It has 2 holes to hang from a key chain.", category_name: "Assistive" },
  { name: "Stress Ball", code: "stress_ball", position: nil, notes: nil, category_name: "Fidget" },
  { name: "Fork and Spoon Support", code: "fork_and_spoon_support", position: nil, notes: "This is an aid for people with difficulty using eating utensils. Forks or spoons with flat bases slide into the 2 slots of this device.", category_name: "Assistive" },
  { name: "Finger Pen Holder (Vertical)", code: "finger_pen_holder", position: nil, notes: "The finger pen holder slides onto the user's finger and a writing utensil. It is useful for those with gripping issues but still have movement in their hand or wrist. The device can be used on the index, middle, ring, or pinky finger.", category_name: "Assistive" },
  { name: "Light Switch Extension Lever", code: "light_switch_extension_lever", position: nil, notes: "This device extends a light switch, making it easier for those with limited grip strength, finger dexterity, or arthritis to flip the light switch.", category_name: "Assistive" },
  { name: "Sturdy Door Knob Lever", code: "sturdy_door_knob_lever", position: nil, notes: "This is an adapter to turn round door knobs into a lever handle. It clamps together with a nut (M5x18) and bolt (M5) - not included. If you aren't getting enough grip on your doorknob, try adding a thin strip of poster putty around the doorknob before clamping the lever on.", category_name: "Assistive" },
  { name: "Bag Holder/Shopping Handle", code: "bag_holder", position: nil, notes: "This device helps carry multiple shopping bags at once.", category_name: "Assistive" },
  { name: "Drinking Straw Holder", code: "drinking_straw_holder", position: nil, notes: "This straw holder makes sure the straw stays in place. The straw holder is made to fit regular sized straws and mounts easily on a drinking glass.", category_name: "Assistive" },
  { name: "Bottle Opener", code: "bottle_opener", position: nil, notes: "This bottle opener is a tool that assists people with arthritis, limited finger dexterity, or other disabilities to open a standard water bottle cap.", category_name: "Assistive" },
  { name: "Signature Guide", code: "signature_guide", position: nil, notes: "The signature guide assists users who have difficulties writing in a specific area with writing their signature and initials on the line.", category_name: "Assistive" },
  { name: "Fidget Cube", code: "fidget_cube", position: nil, notes: nil, category_name: "Fidget" },
  { name: "Thumb Book Holder", code: "thumb_book_holder", position: nil, notes: "The thumb book holder helps keep the book pages open.", category_name: "Assistive" }
].each do |attrs|
  attrs = attrs.dup
  category = Category.find_by!(name: attrs.delete(:category_name))
  create_once!(PrintableModel, { code: attrs[:code] }, attrs.except(:code).merge(category: category))
end

###############################################################################
# 6) Staff User
###############################################################################

StaffUser.find_or_create_by!(email: "robot@tadl.org") do |user|
  user.name = "MAKE Robot"
  user.uid = "robot"
  user.admin = false
end

puts "db:seed complete"
