require "test_helper"

class PrintJobReportTest < ActiveSupport::TestCase
  test "multiple attached model files do not inflate quantity or material totals" do
    date = Date.new(2026, 2, 1)
    job = create_completed_fdm_job(date:, quantity: 2, actual_weight: 50, filament_color: "black")

    3.times do |index|
      job.model_files.attach(
        io: file_fixture("test-model.stl").open,
        filename: "model-#{index}.stl",
        content_type: "model/stl"
      )
    end

    report = PrintJobReport.new(start_date: date, end_date: date)

    assert_equal 1, report.category_counts.values.sum
    assert_equal 2, report.total_quantity
    assert_equal 100, report.filament_grams
    assert_equal({ date => 2 }, report.prints_per_day)
    assert_equal({ date => 100 }, report.filament_per_day)
    assert_equal({ "black" => 2 }, report.filament_color_counts)
    assert_equal 1, report.unique_designs
  end

  test "blank and zero quantity are treated as one copy" do
    date = Date.new(2026, 2, 2)
    create_completed_fdm_job(date:, quantity: nil, actual_weight: 20)
    create_completed_fdm_job(date:, quantity: 0, actual_weight: 30)

    report = PrintJobReport.new(start_date: date, end_date: date)

    assert_equal 2, report.total_quantity
    assert_equal 50, report.filament_grams
    assert_equal({ date => 2 }, report.prints_per_day)
    assert_equal({ date => 50 }, report.filament_per_day)
  end

  test "resin usage also scales by normalized quantity" do
    date = Date.new(2026, 2, 3)
    create_completed_resin_job(date:, quantity: 3, resin_volume_ml: 12)
    create_completed_resin_job(date:, quantity: nil, resin_volume_ml: 8)

    report = PrintJobReport.new(start_date: date, end_date: date)

    assert_equal 4, report.total_quantity
    assert_equal 44, report.resin_ml
  end

  private

  def create_completed_fdm_job(date:, quantity:, actual_weight:, filament_color: nil)
    ensure_base_lookups!

    create_print_job(
      status_code: "archived",
      attrs: {
        print_type: PrintType.find_by!(code: "fdm"),
        completion_date: date,
        quantity: quantity,
        actual_weight: actual_weight,
        filament_color: filament_color,
        url: "https://example.org/fdm/#{SecureRandom.hex(4)}"
      }
    )
  end

  def create_completed_resin_job(date:, quantity:, resin_volume_ml:)
    ensure_base_lookups!

    create_print_job(
      status_code: "archived",
      attrs: {
        print_type: PrintType.find_by!(code: "resin"),
        completion_date: date,
        quantity: quantity,
        resin_volume_ml: resin_volume_ml,
        url: "https://example.org/resin/#{SecureRandom.hex(4)}"
      }
    )
  end
end
