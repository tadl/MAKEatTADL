class PatronMergeService
  class MergeError < StandardError; end

  Result = Struct.new(:winner, :loser, :jobs_moved, :messages_moved, keyword_init: true)

  def self.call(winner:, loser:)
    new(winner:, loser:).call
  end

  def initialize(winner:, loser:)
    @winner = winner
    @loser = loser
  end

  def call
    validate_merge!

    jobs_moved = 0
    messages_moved = 0

    Patron.transaction do
      winner.lock!
      loser.lock!

      if winner.name.blank? && loser.name.present?
        winner.update!(name: loser.name)
      end

      loser.jobs.find_each do |job|
        job.update!(patron: winner)
        jobs_moved += 1
      end

      Message.where(author_type: "Patron", author_id: loser.id).find_each do |message|
        message.update!(author: winner)
        messages_moved += 1
      end

      loser.destroy!
    end

    Result.new(
      winner: winner,
      loser: loser,
      jobs_moved: jobs_moved,
      messages_moved: messages_moved
    )
  end

  private

  attr_reader :winner, :loser

  def validate_merge!
    raise MergeError, "Both patrons must exist." unless winner.is_a?(Patron) && loser.is_a?(Patron)
    raise MergeError, "Both patrons must be saved records." unless winner.persisted? && loser.persisted?
    raise MergeError, "Choose two different patrons to merge." if winner.id == loser.id
  end
end
