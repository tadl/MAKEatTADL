class JobStatistics
  # Returns a hash: { staff_user_id => count, … }
  def self.prints_started(start_date, end_date)
    Job.started_between(start_date.beginning_of_day, end_date.end_of_day)
       .group(:started_by_id).count
  end

  def self.prints_finished(start_date, end_date)
    Job.finished_between(start_date.beginning_of_day, end_date.end_of_day)
       .group(:finished_by_id).count
  end

  # Returns { printer_id => count, … }
  def self.prints_by_printer(start_date, end_date)
    Job.finished_between(start_date.beginning_of_day, end_date.end_of_day)
       .group(:assigned_printer_id).count
  end
end
