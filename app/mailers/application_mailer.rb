# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ->(*) { branded_from_header }, reply_to: ->(*) { branded_reply_to_header }
  layout 'mailer'

  register_interceptor ActionMailerConfigsInterceptor

  register_observer ActionMailerEventsObserver

  before_action do
    ActiveStorage::Current.url_options = Docuseal.default_url_options
  end

  after_action :set_message_metadata
  after_action :set_message_uuid

  def default_url_options
    Docuseal.default_url_options.merge(host: ENV.fetch('EMAIL_HOST', Docuseal.default_url_options[:host]))
  end

  def set_message_metadata
    message.instance_variable_set(:@message_metadata, @message_metadata || {})
  end

  def set_message_uuid
    message['X-Message-Uuid'] = SecureRandom.uuid
  end

  def assign_message_metadata(tag, record)
    @message_metadata = (@message_metadata || {}).merge(
      'tag' => tag,
      'record_id' => record.id,
      'record_type' => record.class.name
    )
  end

  def put_metadata(attrs)
    @message_metadata = (@message_metadata || {}).merge(attrs)
  end

  private

  def branding_mail_account
    account = @current_account if defined?(@current_account)
    account ||= @account if defined?(@account)
    account ||= @resource&.account if defined?(@resource)
    account ||= @submitter&.account if defined?(@submitter)
    account ||= @template&.account if defined?(@template)

    account
  end

  def branded_from_header
    account = branding_mail_account

    if account.present?
      %("#{account.sender_name.delete('"')}" <#{account.support_email}>)
    else
      %("#{Docuseal.product_name.delete('"')}" <#{Docuseal::SUPPORT_EMAIL}>)
    end
  end

  def branded_reply_to_header
    branding_mail_account&.default_reply_to
  end
end
