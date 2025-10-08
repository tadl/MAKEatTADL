# lib/rails_admin/config/actions/conversation.rb
require 'rails_admin/config/actions'
require 'rails_admin/config/actions/base'

module RailsAdmin
  module Config
    module Actions
      class Conversation < Base
        RailsAdmin::Config::Actions.register(self)

        # this is a member-only action
        register_instance_option :member do
          true
        end

        register_instance_option :visible? do
          bindings[:abstract_model].model == ::Job && authorized?
        end

        register_instance_option :link_icon do
          'fa fa-comments'
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        # the URL will be /admin/job/:id/conversation
        register_instance_option :route_fragment do
          'conversation'
        end

        register_instance_option :route_action do
          :conversation
        end

        register_instance_option :controller do
          proc do
            @job          = @abstract_model.model.find(params[:id])
            @conversation = @job.conversation || @job.build_conversation

            if current_staff_user
              Notification
                .where(staff_user: current_staff_user, message: @conversation.messages)
                .unread
                .find_each(&:mark_read!)
            end

            if request.get?
              # ==== MARK PATRON MESSAGES READ ====
              @conversation.messages.unread.find_each(&:update_read_at!)

              render @action.template_name

            elsif request.post?
              # ==== STAFF POST ====
              body            = params.dig(:conversation, :message_body).to_s
              staff_only_flag = params.dig(:conversation, :staff_note_only) == '1'

              # --- FORCE STAFF NOTE WHENEVER THERE ARE @MENTIONS ---
              has_mentions = body.match?(/@\w+/)
              staff_only_flag ||= has_mentions

              msg = @conversation.messages.create!(
                body:            body,
                author:          current_staff_user,
                staff_note_only: staff_only_flag
              )

              # extract @mentions and notify staff
              usernames = body.scan(/@(\w+)/).flatten.uniq
              usernames.each do |username|
                staff_email = "#{username}@#{ENV.fetch('GOOGLE_DOMAIN')}"
                if (staff = StaffUser.find_by(email: staff_email))
                  Notification.create!(staff_user: staff, message: msg)
                  MentionMailer.user_mentioned(staff, msg).deliver_later
                end
              end

              # attach any uploaded images
              if params.dig(:conversation, :images).present?
                Array(params.dig(:conversation, :images)).each { |upload| msg.images.attach(upload) }
              end

              # only email patron when not a staff-only note (mentions force staff-only)
              unless staff_only_flag
                JobMailer.notify_patron(msg).deliver_later
              end

              # Turbo-stream replace the messages list and reset the form
              render turbo_stream: [
                turbo_stream.replace(
                  'messages',
                  partial: 'rails_admin/main/conversation_messages',
                  locals: { conversation: @conversation }
                ),
                turbo_stream.replace(
                  'conversation_form',
                  partial: 'rails_admin/main/conversation_form',
                  locals: { job: @job, conversation: @conversation }
                )
              ]
            end
          end
        end
      end
    end
  end
end
