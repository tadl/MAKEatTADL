namespace :demo do
  desc "Add 300 synthetic local-development jobs (COUNT=1..1000); preserve existing records and edits"
  task seed: :environment do
    result = Development::DemoData.new(count: ENV.fetch("COUNT", "300"), model_file: ENV["MODEL_FILE"],
      replace_library_files: ENV["REPLACE_LIBRARY_FILES"] == "1").call
    puts JSON.pretty_generate(result)
  rescue Development::DemoData::Error => error
    abort error.message
  end
end
