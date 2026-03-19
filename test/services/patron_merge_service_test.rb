require "test_helper"

class PatronMergeServiceTest < ActiveSupport::TestCase
  test "moves jobs and patron-authored messages to the winning patron" do
    winner = create_patron(email: unique_email("winner"), name: "Correct Email")
    loser = create_patron(email: unique_email("loser"), name: "Typo Email")
    job = create_print_job(patron: loser)
    outsider = create_patron(email: unique_email("outsider"))

    patron_message = job.conversation.messages.create!(body: "Reply from patron", author: loser)
    outsider_message = job.conversation.messages.create!(body: "Someone else", author: outsider)

    result = PatronMergeService.call(winner:, loser:)

    assert_equal winner, result.winner
    assert_equal 1, result.jobs_moved
    assert_equal 1, result.messages_moved
    assert_equal winner, job.reload.patron
    assert_equal winner, patron_message.reload.author
    assert_equal outsider, outsider_message.reload.author
    assert_not Patron.exists?(loser.id)
  end

  test "copies the losing patron name when the winner name is blank" do
    winner = create_patron(email: unique_email("winner"), name: nil)
    loser = create_patron(email: unique_email("loser"), name: "Known Name")

    PatronMergeService.call(winner:, loser:)

    assert_equal "Known Name", winner.reload.name
  end

  test "rejects merging a patron into itself" do
    patron = create_patron

    error = assert_raises(PatronMergeService::MergeError) do
      PatronMergeService.call(winner: patron, loser: patron)
    end

    assert_match(/different patrons/i, error.message)
  end
end
