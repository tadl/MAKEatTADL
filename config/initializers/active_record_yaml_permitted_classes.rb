# config/initializers/active_record_yaml_permitted_classes.rb

Rails.application.config.active_record.yaml_column_permitted_classes ||= []
Rails.application.config.active_record.yaml_column_permitted_classes += [
  ActiveSupport::TimeWithZone,
  BigDecimal
]
