# db/seeds.rb

###############################################################################
# 1) Filament Colors
###############################################################################

[
  { name: "Green",      code: "green",       position: 1 },
  { name: "Pink",       code: "pink",        position: 2 },
  { name: "Yellow",     code: "yellow",      position: 3 },
  { name: "Red",        code: "red",         position: 4 },
  { name: "White",      code: "white",       position: 5 },
  { name: "Black",      code: "black",       position: 6 },
  { name: "Orange",     code: "orange",      position: 7 },
  { name: "Blue",       code: "blue",        position: 8 },
  { name: "Purple",     code: "purple",      position: 9 },
  { name: "Gray",       code: "gray",        position: 10 },
  { name: "Light Cyan", code: "light_cyan",  position: 11 },
  { name: "Other",      code: "other",       position: 12 }
].each do |attrs|
  fc = FilamentColor.find_or_initialize_by(code: attrs[:code])
  fc.name     = attrs[:name]
  fc.position = attrs[:position]
  fc.save! if fc.changed?
end

###############################################################################
# 2) Pickup Locations
###############################################################################

[
  { name: "East Bay",   code: "ebb",  position: 2, active: true,  scanner: false, fdm_printer: true,  resin_printer: false },
  { name: "Kingsley",   code: "kbl",  position: 3, active: false, scanner: false, fdm_printer: true,  resin_printer: false },
  { name: "Woodmere",   code: "wood", position: 1, active: true,  scanner: true,  fdm_printer: true,  resin_printer: true  }
].each do |attrs|
  pl = PickupLocation.find_or_initialize_by(code: attrs[:code])
  pl.assign_attributes(attrs.except(:code))
  pl.save! if pl.changed?
end

###############################################################################
# 3) Print Types
###############################################################################

[
  { name: "FDM",   code: "fdm",   position: 1 },
  { name: "Resin", code: "resin", position: 2 }
].each do |attrs|
  pt = PrintType.find_or_initialize_by(code: attrs[:code])
  pt.name     = attrs[:name]
  pt.position = attrs[:position]
  pt.save! if pt.changed?
end

###############################################################################
# 4) Statuses
###############################################################################

[
  { name: "Requested",             code: "requested",               position: 0 },
  { name: "Information Requested", code: "information_requested",   position: 1 },
  { name: "Queued",                code: "queued",                  position: 2 },
  { name: "Printing",              code: "printing",                position: 3 },
  { name: "Ready for pickup",      code: "ready_for_pickup",        position: 4 },
  { name: "Archived",              code: "archived",                position: 5 },
  { name: "Ongoing",               code: "ongoing",                 position: 6 },
  { name: "Cancelled",             code: "cancelled",               position: 7 }
].each do |attrs|
  s = Status.find_or_initialize_by(code: attrs[:code])
  s.name     = attrs[:name]
  s.position = attrs[:position]
  s.save! if s.changed?
end

###############################################################################
# 5) Categories
###############################################################################

[
  { name: "Patron",     position: 1 },
  { name: "Staff",      position: 2 },
  { name: "Assistive",  position: 3 },
  { name: "Fidget",     position: 4 }
].each do |attrs|
  c = Category.find_or_initialize_by(name: attrs[:name])
  c.position = attrs[:position]
  c.save! if c.changed?
end

###############################################################################
# 6) Printable Models
###############################################################################

[
  { name: "Calming Comb",                 code: "calming_comb",                position: 0, notes: nil,                                                                                  category_name: "Fidget"    },
  { name: "Concentric Flower",            code: "concentric_flower",           position: 1, notes: nil,                                                                                  category_name: "Fidget"    },
  { name: "Fidget Spinner",               code: "fidget_spinner",              position: 2, notes: nil,                                                                                  category_name: "Fidget"    },
  { name: "Key Turner",                   code: "key_turner",                  position: 3, notes: "The key turner allows people with arthritis or other disabilities to grasp their keys better. The key turner fits most standard size keys. It has 2 holes to hang from a key chain.", category_name: "Assistive" },
  { name: "Stress Ball",                  code: "stress_ball",                 position: nil, notes: nil,                                                                                  category_name: "Fidget"    },
  { name: "Fork and Spoon Support",       code: "fork_and_spoon_support",      position: nil, notes: "This is an aid for people with difficulty using eating utensils. Forks or spoons with flat bases slide into the 2 slots of this device.",                             category_name: "Assistive" },
  { name: "Finger Pen Holder (Vertical)", code: "finger_pen_holder",           position: nil, notes: "The finger pen holder slides onto the user’s finger and a writing utensil. It is useful for those with gripping issues but still have movement in their hand or wrist. The device can be used on the index, middle, ring, or pinky finger.", category_name: "Assistive" },
  { name: "Light Switch Extension Lever", code: "light_switch_extension_lever", position: nil, notes: "This device extends a light switch, making it easier for those with limited grip strength, finger dexterity, or arthritis to flip the light switch.",          category_name: "Assistive" },
  { name: "Sturdy Door Knob Lever",      code: "sturdy_door_knob_lever",      position: nil, notes: "This is an adapter to turn round door knobs into a lever handle. It clamps together with a nut (M5x18) and bolt (M5) - not included. If you aren't getting enough grip on your doorknob, try adding a thin strip of poster putty around the doorknob before clamping the lever on.", category_name: "Assistive" },
  { name: "Bag Holder/Shopping Handle",   code: "bag_holder",                  position: nil, notes: "This device helps carry multiple shopping bags at once.",                                               category_name: "Assistive" },
  { name: "Drinking Straw Holder",       code: "drinking_straw_holder",       position: nil, notes: "This straw holder makes sure the straw stays in place. The straw holder is made to fit regular sized straws and mounts easily on a drinking glass.",            category_name: "Assistive" },
  { name: "Bottle Opener",                code: "bottle_opener",               position: nil, notes: "This bottle opener is a tool that assists people with arthritis, limited finger dexterity,  or other disabilities to open a standard water bottle cap.",         category_name: "Assistive" },
  { name: "Signature Guide",              code: "signature_guide",             position: nil, notes: "The signature guide assists users who have difficulties writing in a specific area with writing their signature and initials on the line.",                   category_name: "Assistive" },
  { name: "Fidget Cube",                  code: "fidget_cube",                 position: nil, notes: nil,                                                                                  category_name: "Fidget"    },
  { name: "Thumb Book Holder",            code: "thumb_book_holder",           position: nil, notes: "The thumb book holder helps keep the book pages open.",                                                  category_name: "Assistive" }
].each do |attrs|
  cat = Category.find_by!(name: attrs.delete(:category_name))
  pm  = PrintableModel.find_or_initialize_by(code: attrs[:code])
  pm.name       = attrs[:name]
  pm.position   = attrs[:position]
  pm.notes      = attrs[:notes]
  pm.category   = cat
  pm.save! if pm.changed?
end

###############################################################################
# 7) Printers
###############################################################################

[
  { name: "Bambi",   printer_type: "FDM", printer_model: "Bambu P1S",           bed_size: "256x256x256", location: "Outside Tech Center", pickup_location_code: "wood", print_type_code: "fdm" },
  { name: "Pee-wee", printer_type: "FDM", printer_model: "Bambu P1S",           bed_size: "256x256x256", location: "Main Floor by Stairs",  pickup_location_code: "wood", print_type_code: "fdm" },
  { name: "Prusa XL",printer_type: "FDM", printer_model: "Prusa XL",            bed_size: "360x360x360", location: "Technology Workroom",   pickup_location_code: "wood", print_type_code: "fdm" },
  { name: "Prusa 02",printer_type: "FDM",   printer_model: "Prusa MK3s",         bed_size: "250x210x210", location: nil,                    pickup_location_code: "ebb", print_type_code: "fdm" },
  { name: "Prusa 01",printer_type: "FDM",   printer_model: "Prusa MK3s",         bed_size: "250x210x210", location: nil,                    pickup_location_code: "kbl",  print_type_code: "fdm" },
  { name: "Saturn",  printer_type: "Resin",   printer_model: "Elegoo Saturn 3 Ultra", bed_size: "218.88x122.88x260", location: "Technology Workroom", pickup_location_code: "wood", print_type_code: "resin" }
].each do |attrs|
  plc = PickupLocation.find_by!(code: attrs.delete(:pickup_location_code))
  pt  = PrintType.find_by!(code: attrs.delete(:print_type_code))
  pr  = Printer.find_or_initialize_by(name: attrs[:name])
  pr.printer_type      = attrs[:printer_type]
  pr.printer_model     = attrs[:printer_model]
  pr.bed_size          = attrs[:bed_size]
  pr.location          = attrs[:location]
  pr.pickup_location   = plc
  pr.print_type        = pt
  pr.save! if pr.changed?
end

puts "✅   db:seed complete!"
